const CurrencyConversionRate = require('../models/currencyConversionRate');
const CurrencyDefinition = require('../models/currencyDefinition');
const {
  getSupportedCurrencyDefinitions,
  getSupportedCurrencyCodes,
  normalizeCurrencyCode,
} = require('../utils/supportedCurrencies');

const normalizeCurrency = (currency) =>
  (currency || '').toString().trim().toUpperCase();

const buildGraph = (rows) => {
  const graph = new Map();
  const seenPairs = new Set();
  for (const row of rows) {
    const from = normalizeCurrency(row.baseCurrency);
    const to = normalizeCurrency(row.quoteCurrency);
    const pairKey = `${from}->${to}`;
    if (seenPairs.has(pairKey)) continue;
    seenPairs.add(pairKey);
    if (!graph.has(from)) graph.set(from, []);
    graph.get(from).push({
      to,
      rate: Number(row.rate || 0),
      isAutoDerived: row.isAutoDerived === true,
      updatedAt: row.updatedAt,
      updatedBy: row.updatedBy,
    });
  }
  return graph;
};

const resolveRate = (graph, from, to, visited = new Set()) => {
  if (from === to) {
    return { rate: 1, path: [from], hops: 0 };
  }
  if (visited.has(from)) return null;
  visited.add(from);

  const neighbors = graph.get(from) || [];
  for (const edge of neighbors) {
    if (!edge.rate) continue;
    if (edge.to === to) {
      return {
        rate: edge.rate,
        path: [from, to],
        hops: 1,
      };
    }
    const next = resolveRate(graph, edge.to, to, new Set(visited));
    if (next) {
      return {
        rate: edge.rate * next.rate,
        path: [from, ...next.path],
        hops: next.hops + 1,
      };
    }
  }

  return null;
};

const buildMatrix = (rows, supportedCurrencies) => {
  const graph = buildGraph(rows);
  const matrix = [];

  for (const baseCurrency of supportedCurrencies) {
    for (const quoteCurrency of supportedCurrencies) {
      const resolved = resolveRate(graph, baseCurrency, quoteCurrency);
      matrix.push({
        baseCurrency,
        quoteCurrency,
        rate: resolved ? Number(resolved.rate.toFixed(8)) : null,
        available: Boolean(resolved),
        mode:
          baseCurrency === quoteCurrency
              ? 'identity'
              : resolved && resolved.hops <= 1
                  ? 'manual'
                  : resolved
                      ? 'calculated'
                      : 'missing',
        path: resolved?.path || [],
      });
    }
  }

  return matrix;
};

exports.getAdminCurrencyConversions = async (_req, res) => {
  try {
    const currencyDefinitions = await getSupportedCurrencyDefinitions();
    const supportedCurrencies = currencyDefinitions.map((item) => item.code);
    const rows = await CurrencyConversionRate.find({
      baseCurrency: { $in: supportedCurrencies },
      quoteCurrency: { $in: supportedCurrencies },
    })
      .sort({ updatedAt: -1 })
      .populate('updatedBy', 'name email')
      .lean();

    const matrix = buildMatrix(rows, supportedCurrencies);
    const latestUpdatedAt =
      rows.reduce((latest, row) => {
        const current = new Date(row.updatedAt || 0).getTime();
        return current > latest ? current : latest;
      }, 0) || null;

    res.json({
      supportedCurrencies,
      currencyDefinitions,
      latestUpdatedAt: latestUpdatedAt ? new Date(latestUpdatedAt) : null,
      directRates: rows.map((row) => ({
        _id: row._id,
        baseCurrency: row.baseCurrency,
        quoteCurrency: row.quoteCurrency,
        rate: Number(row.rate || 0),
        isAutoDerived: row.isAutoDerived === true,
        updatedAt: row.updatedAt,
        updatedBy: row.updatedBy
          ? {
              _id: row.updatedBy._id,
              name: row.updatedBy.name,
              email: row.updatedBy.email,
            }
          : null,
      })),
      matrix,
    });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.upsertAdminCurrencyConversion = async (req, res) => {
  try {
    const supportedCurrencies = await getSupportedCurrencyCodes();
    const baseCurrency = normalizeCurrency(req.body.baseCurrency);
    const quoteCurrency = normalizeCurrency(req.body.quoteCurrency);
    const rate = Number(req.body.rate);

    if (!supportedCurrencies.includes(baseCurrency)) {
      return res.status(400).json({ error: 'Unsupported base currency' });
    }
    if (!supportedCurrencies.includes(quoteCurrency)) {
      return res.status(400).json({ error: 'Unsupported quote currency' });
    }
    if (baseCurrency === quoteCurrency) {
      return res
        .status(400)
        .json({ error: 'Base and quote currencies must be different' });
    }
    if (!Number.isFinite(rate) || rate <= 0) {
      return res.status(400).json({ error: 'Rate must be greater than 0' });
    }

    const directRate = Number(rate.toFixed(8));
    const inverseRate = Number((1 / rate).toFixed(8));

    await CurrencyConversionRate.findOneAndUpdate(
      { baseCurrency, quoteCurrency },
      {
        baseCurrency,
        quoteCurrency,
        rate: directRate,
        updatedBy: req.user._id,
        isAutoDerived: false,
      },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );

    await CurrencyConversionRate.findOneAndUpdate(
      { baseCurrency: quoteCurrency, quoteCurrency: baseCurrency },
      {
        baseCurrency: quoteCurrency,
        quoteCurrency: baseCurrency,
        rate: inverseRate,
        updatedBy: req.user._id,
        isAutoDerived: true,
      },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );

    const rows = await CurrencyConversionRate.find({
      baseCurrency: { $in: supportedCurrencies },
      quoteCurrency: { $in: supportedCurrencies },
    })
      .sort({ updatedAt: -1 })
      .populate('updatedBy', 'name email')
      .lean();

    res.json({
      message: `Saved ${baseCurrency} -> ${quoteCurrency} conversion successfully.`,
      supportedCurrencies,
      matrix: buildMatrix(rows, supportedCurrencies),
      directRates: rows,
    });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.addSupportedCurrency = async (req, res) => {
  try {
    const code = normalizeCurrencyCode(req.body.code);
    const symbol = (req.body.symbol || '').toString().trim();
    const label = (req.body.label || '').toString().trim();

    if (!code || code.length < 3 || code.length > 6) {
      return res.status(400).json({ error: 'Currency code must be 3 to 6 characters.' });
    }
    if (!symbol) {
      return res.status(400).json({ error: 'Currency symbol is required.' });
    }

    const currency = await CurrencyDefinition.findOneAndUpdate(
      { code },
      {
        code,
        symbol,
        label,
        active: true,
        updatedBy: req.user._id,
      },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );

    const currencyDefinitions = await getSupportedCurrencyDefinitions();
    res.status(201).json({
      message: `${code} is now available for conversions and group expenses.`,
      currency,
      currencyDefinitions,
      supportedCurrencies: currencyDefinitions.map((item) => item.code),
    });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getSupportedCurrencies = async (_req, res) => {
  try {
    const currencyDefinitions = await getSupportedCurrencyDefinitions();
    res.json({
      currencies: currencyDefinitions,
      supportedCurrencies: currencyDefinitions.map((item) => item.code),
    });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getPublicCurrencyMatrix = async (_req, res) => {
  try {
    const currencyDefinitions = await getSupportedCurrencyDefinitions();
    const supportedCurrencies = currencyDefinitions.map((item) => item.code);
    const rows = await CurrencyConversionRate.find({
      baseCurrency: { $in: supportedCurrencies },
      quoteCurrency: { $in: supportedCurrencies },
    })
      .sort({ updatedAt: -1 })
      .lean();

    const matrix = buildMatrix(rows, supportedCurrencies);

    res.json({
      currencies: currencyDefinitions,
      supportedCurrencies,
      matrix,
      displayBaseCurrency: 'INR',
      generatedAt: new Date(),
    });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};
