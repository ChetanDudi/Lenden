const CurrencyConversionRate = require('../models/currencyConversionRate');
const CurrencyDefinition = require('../models/currencyDefinition');
const {
  getSupportedCurrencyDefinitions,
  getSupportedCurrencyCodes,
  normalizeCurrencyCode,
} = require('../utils/supportedCurrencies');

const normalizeCurrency = (currency) =>
  (currency || '').toString().trim().toUpperCase();

// ECB-supported currencies via Frankfurter API (free, no key)
const FRANKFURTER_SUPPORTED = new Set([
  'AUD','BGN','BRL','CAD','CHF','CNY','CZK','DKK','EUR','GBP',
  'HKD','HUF','IDR','ILS','INR','ISK','JPY','KRW','MXN','MYR',
  'NOK','NZD','PHP','PLN','RON','SEK','SGD','THB','TRY','USD','ZAR',
]);

// In-memory throttle: avoid hammering ECB on every single request
let _lastAutoSyncMs = 0;
const AUTO_SYNC_INTERVAL_MS = 60 * 60 * 1000; // 1 hour

// Shared ECB fetch + DB save logic (used by syncLiveRates route and cron)
async function _runEcbSync(updatedBy = null) {
  const currencyDefinitions = await getSupportedCurrencyDefinitions();
  const supportedCurrencies = currencyDefinitions.map((item) => item.code);

  if (supportedCurrencies.length < 2) return { saved: 0, rateDate: null };

  const base =
    supportedCurrencies.find((c) => c === 'USD') ||
    supportedCurrencies.find((c) => c === 'EUR') ||
    supportedCurrencies.find((c) => FRANKFURTER_SUPPORTED.has(c));

  if (!base) return { saved: 0, rateDate: null };

  const targets = supportedCurrencies.filter(
    (c) => c !== base && FRANKFURTER_SUPPORTED.has(c)
  );
  if (targets.length === 0) return { saved: 0, rateDate: null };

  const url = `https://api.frankfurter.app/latest?from=${base}&to=${targets.join(',')}`;
  const fetchRes = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (!fetchRes.ok) {
    const text = await fetchRes.text().catch(() => '');
    throw new Error(`ECB API ${fetchRes.status}: ${text}`);
  }

  const data = await fetchRes.json();
  const ops = [];
  let saved = 0;

  for (const [quoteCurrency, rawRate] of Object.entries(data.rates || {})) {
    if (!supportedCurrencies.includes(quoteCurrency)) continue;
    const directRate = Number(Number(rawRate).toFixed(8));
    const inverseRate = Number((1 / rawRate).toFixed(8));

    ops.push(
      CurrencyConversionRate.findOneAndUpdate(
        { baseCurrency: base, quoteCurrency },
        { baseCurrency: base, quoteCurrency, rate: directRate, ...(updatedBy && { updatedBy }), isAutoDerived: false },
        { upsert: true, new: true, setDefaultsOnInsert: true }
      ),
      CurrencyConversionRate.findOneAndUpdate(
        { baseCurrency: quoteCurrency, quoteCurrency: base },
        { baseCurrency: quoteCurrency, quoteCurrency: base, rate: inverseRate, ...(updatedBy && { updatedBy }), isAutoDerived: true },
        { upsert: true, new: true, setDefaultsOnInsert: true }
      )
    );
    saved++;
  }

  await Promise.all(ops);
  _lastAutoSyncMs = Date.now();
  return { saved, rateDate: data.date, base, supportedCurrencies };
}

// Called by cron and exported for app.js
async function autoSyncCurrencyRates() {
  try {
    if (Date.now() - _lastAutoSyncMs < AUTO_SYNC_INTERVAL_MS) return; // In-memory gate
    await _runEcbSync(null);
  } catch (err) {
    console.error('❌ Currency auto-sync failed:', err.message);
  }
}
exports.autoSyncCurrencyRates = autoSyncCurrencyRates;

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

exports.syncLiveRates = async (req, res) => {
  try {
    const { saved, rateDate, base, supportedCurrencies } = await _runEcbSync(req.user._id);

    if (saved === 0) {
      return res.status(422).json({ error: 'None of your currencies are supported by the live rate source (Frankfurter/ECB).' });
    }

    const rows = await CurrencyConversionRate.find({
      baseCurrency: { $in: supportedCurrencies },
      quoteCurrency: { $in: supportedCurrencies },
    }).sort({ updatedAt: -1 }).populate('updatedBy', 'name email').lean();

    res.json({
      message: `Synced ${saved} pair${saved !== 1 ? 's' : ''} using live ECB rates (base: ${base}, date: ${rateDate}).`,
      rateDate,
      savedPairs: saved,
      supportedCurrencies,
      matrix: buildMatrix(rows, supportedCurrencies),
      directRates: rows,
    });
  } catch (err) {
    console.error('❌ syncLiveRates error:', err);
    if (err.name === 'TimeoutError') {
      return res.status(504).json({ error: 'Live rate API timed out. Please try again.' });
    }
    res.status(500).json({ error: 'Failed to sync live rates.' });
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
  // Fire-and-forget: silently refresh ECB rates in background if stale (> 1 hour)
  autoSyncCurrencyRates();

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
