const QuickTransaction = require('../models/quickTransaction');
const Transaction = require('../models/transaction');
const GroupTransaction = require('../models/groupTransaction');
const User = require('../models/user');

exports.getReportSummary = async (req, res) => {
  try {
    const userId = req.user._id;
    const user = await User.findById(userId).select('email name').lean();
    if (!user) return res.status(404).json({ message: 'User not found' });
    const email = user.email;

    const endDate = req.query.endDate ? new Date(req.query.endDate) : new Date();
    const startDate = req.query.startDate
      ? new Date(req.query.startDate)
      : new Date(endDate.getFullYear(), endDate.getMonth() - 5, 1);

    // Previous period (same duration, immediately before) for comparison
    const periodMs = endDate.getTime() - startDate.getTime();
    const prevEndDate = new Date(startDate.getTime() - 1);
    const prevStartDate = new Date(startDate.getTime() - periodMs);

    const [quickTxns, secureTxns, groupTxns, prevQuickTxns, prevSecureTxns] = await Promise.all([
      QuickTransaction.find({ creatorEmail: email, date: { $gte: startDate, $lte: endDate } }).lean(),
      Transaction.find({
        $or: [{ userEmail: email }, { counterpartyEmail: email }],
        createdAt: { $gte: startDate, $lte: endDate },
      }).lean(),
      GroupTransaction.find({ 'members.user': userId }).lean(),
      QuickTransaction.find({ creatorEmail: email, date: { $gte: prevStartDate, $lte: prevEndDate } }).lean(),
      Transaction.find({
        $or: [{ userEmail: email }, { counterpartyEmail: email }],
        createdAt: { $gte: prevStartDate, $lte: prevEndDate },
      }).lean(),
    ]);

    // Current period breakdowns
    const mySecure = secureTxns.filter((t) => t.userEmail === email);
    const prevMySecure = prevSecureTxns.filter((t) => t.userEmail === email);

    const quickLent = quickTxns.filter((t) => t.role === 'lender').reduce((s, t) => s + (t.amount || 0), 0);
    const quickBorrowed = quickTxns.filter((t) => t.role === 'borrower').reduce((s, t) => s + (t.amount || 0), 0);
    const quickCleared = quickTxns.filter((t) => t.cleared).length;

    const secureLent = mySecure.filter((t) => t.role === 'lender').reduce((s, t) => s + (t.amount || 0), 0);
    const secureBorrowed = mySecure.filter((t) => t.role === 'borrower').reduce((s, t) => s + (t.amount || 0), 0);
    const secureCleared = mySecure.filter((t) => t.userCleared).length;

    const currentLent = quickLent + secureLent;
    const currentBorrowed = quickBorrowed + secureBorrowed;

    // Previous period totals
    const prevLent = [...prevQuickTxns.filter(t => t.role === 'lender'), ...prevMySecure.filter(t => t.role === 'lender')].reduce((s, t) => s + (t.amount || 0), 0);
    const prevBorrowed = [...prevQuickTxns.filter(t => t.role === 'borrower'), ...prevMySecure.filter(t => t.role === 'borrower')].reduce((s, t) => s + (t.amount || 0), 0);
    const prevTxnCount = prevQuickTxns.length + prevMySecure.length;
    const currTxnCount = quickTxns.length + mySecure.length;

    // Group breakdown — per group
    let groupExpenseTotal = 0;
    let groupUserShare = 0;
    const groupExpenses = [];
    const groupBreakdown = [];

    for (const g of groupTxns) {
      let gTotal = 0, gMyShare = 0;
      const gCatMap = {};
      const memberMap = {};

      for (const exp of g.expenses || []) {
        const expDate = new Date(exp.date);
        if (expDate < startDate || expDate > endDate) continue;

        gTotal += exp.amount || 0;
        groupExpenseTotal += exp.amount || 0;

        const split = (exp.split || []).find((s) => s.user && s.user.toString() === userId.toString());
        if (split) {
          gMyShare += split.amount || 0;
          groupUserShare += split.amount || 0;
          groupExpenses.push({ amount: exp.amount || 0, date: exp.date, category: exp.category || 'other', groupTitle: g.title });
        }

        // Member share tracking
        for (const s of (exp.split || [])) {
          const uid = s.user?.toString() || 'unknown';
          if (!memberMap[uid]) memberMap[uid] = { share: 0 };
          memberMap[uid].share += s.amount || 0;
        }

        // Category breakdown per group
        const cat = exp.category || 'other';
        if (!gCatMap[cat]) gCatMap[cat] = { count: 0, amount: 0 };
        gCatMap[cat].count++;
        gCatMap[cat].amount += exp.amount || 0;
      }

      const myBalance = (g.balances || []).find(b => b.user?.toString() === userId.toString());

      if (gTotal > 0 || (myBalance?.balance || 0) !== 0) {
        groupBreakdown.push({
          id: g._id?.toString(),
          title: g.title,
          memberCount: (g.members || []).length,
          totalExpenses: gTotal,
          yourShare: gMyShare,
          othersContribution: gTotal - gMyShare,
          netBalance: myBalance?.balance || 0,
          topCategories: Object.entries(gCatMap)
            .sort((a, b) => b[1].amount - a[1].amount)
            .slice(0, 3)
            .map(([cat, d]) => ({ category: cat, ...d })),
        });
      }
    }

    // Category breakdown with % of total and trend vs previous period
    const catMap = {};
    const addToCat = (cat, amount) => {
      const c = cat || 'other';
      if (!catMap[c]) catMap[c] = { count: 0, amount: 0 };
      catMap[c].count++;
      catMap[c].amount += amount || 0;
    };
    for (const t of quickTxns) addToCat(t.category, t.amount);
    for (const t of mySecure) addToCat(t.category, t.amount);
    for (const e of groupExpenses) addToCat(e.category, e.amount);

    const prevCatMap = {};
    const addToPrevCat = (cat, amount) => {
      const c = cat || 'other';
      if (!prevCatMap[c]) prevCatMap[c] = { count: 0, amount: 0 };
      prevCatMap[c].count++;
      prevCatMap[c].amount += amount || 0;
    };
    for (const t of prevQuickTxns) addToPrevCat(t.category, t.amount);
    for (const t of prevMySecure) addToPrevCat(t.category, t.amount);

    const totalCatAmount = Object.values(catMap).reduce((s, c) => s + c.amount, 0);
    const categories = Object.entries(catMap)
      .map(([category, d]) => {
        const prev = prevCatMap[category];
        return {
          category,
          count: d.count,
          amount: d.amount,
          percentage: totalCatAmount > 0 ? Math.round((d.amount / totalCatAmount) * 100) : 0,
          prevAmount: prev?.amount || 0,
          trend: prev && prev.amount > 0 ? Math.round(((d.amount - prev.amount) / prev.amount) * 100) : null,
        };
      })
      .sort((a, b) => b.amount - a.amount)
      .filter((c) => c.count > 0);

    // Monthly trend (6 buckets back from endDate)
    const months = Array.from({ length: 6 }, (_, i) => {
      const d = new Date(endDate.getFullYear(), endDate.getMonth() - 5 + i, 1);
      return {
        year: d.getFullYear(),
        month: d.getMonth(),
        label: d.toLocaleString('en', { month: 'short' }) + " '" + String(d.getFullYear()).slice(2),
        lent: 0,
        borrowed: 0,
        group: 0,
      };
    });

    const addToMonths = (items, dateField, lentFn, borrowedFn, groupFn) => {
      for (const item of items) {
        const d = new Date(item[dateField]);
        if (isNaN(d.getTime())) continue;
        const idx = months.findIndex((m) => m.year === d.getFullYear() && m.month === d.getMonth());
        if (idx !== -1) {
          months[idx].lent += lentFn(item) || 0;
          months[idx].borrowed += borrowedFn(item) || 0;
          if (groupFn) months[idx].group += groupFn(item) || 0;
        }
      }
    };

    addToMonths(quickTxns, 'date', (t) => t.role === 'lender' ? t.amount : 0, (t) => t.role === 'borrower' ? t.amount : 0, null);
    addToMonths(mySecure, 'createdAt', (t) => t.role === 'lender' ? t.amount : 0, (t) => t.role === 'borrower' ? t.amount : 0, null);
    addToMonths(groupExpenses, 'date', () => 0, () => 0, (e) => e.amount);

    // Top counterparties
    const cpMap = {};
    const addCp = (cpEmail, amt) => {
      if (!cpMap[cpEmail]) cpMap[cpEmail] = { email: cpEmail, count: 0, netAmount: 0, totalLent: 0, totalBorrowed: 0 };
      cpMap[cpEmail].count++;
      if (amt >= 0) cpMap[cpEmail].totalLent += amt;
      else cpMap[cpEmail].totalBorrowed += Math.abs(amt);
      cpMap[cpEmail].netAmount += amt || 0;
    };
    for (const t of quickTxns) {
      const cp = (t.users || []).find((u) => u !== email);
      if (cp) addCp(cp, t.role === 'lender' ? t.amount : -t.amount);
    }
    for (const t of mySecure) {
      if (t.counterpartyEmail) addCp(t.counterpartyEmail, t.role === 'lender' ? t.amount : -t.amount);
    }
    const topCounterparties = Object.values(cpMap).sort((a, b) => b.count - a.count).slice(0, 7);

    // Advanced stats
    const allAmounts = [...quickTxns, ...mySecure].map(t => t.amount || 0).filter(a => a > 0);
    const highestTxn = allAmounts.length > 0 ? Math.max(...allAmounts) : 0;
    const lowestTxn = allAmounts.length > 0 ? Math.min(...allAmounts) : 0;
    const avgTxn = allAmounts.length > 0 ? allAmounts.reduce((s, a) => s + a, 0) / allAmounts.length : 0;

    const daysInPeriod = Math.max(1, Math.round(periodMs / (1000 * 60 * 60 * 24)));
    const avgDailySpend = (currentLent + currentBorrowed + groupExpenseTotal) / daysInPeriod;

    // Pending
    const pendingQuick = quickTxns.filter(t => !t.cleared);
    const pendingSecure = mySecure.filter(t => !t.userCleared);
    const pendingCount = pendingQuick.length + pendingSecure.length;
    const pendingAmount = [...pendingQuick, ...pendingSecure].reduce((s, t) => s + (t.amount || 0), 0);

    // Daily spending map for heat map
    const dailySpending = {};
    for (const t of quickTxns) {
      const d = new Date(t.date);
      if (isNaN(d.getTime())) continue;
      const key = d.toISOString().split('T')[0];
      dailySpending[key] = (dailySpending[key] || 0) + (t.amount || 0);
    }
    for (const t of mySecure) {
      const d = new Date(t.createdAt);
      if (isNaN(d.getTime())) continue;
      const key = d.toISOString().split('T')[0];
      dailySpending[key] = (dailySpending[key] || 0) + (t.amount || 0);
    }

    // Weekly breakdown (last 4 weeks within period)
    const weeklyBreakdown = Array.from({ length: 4 }, (_, i) => {
      const weekEnd = new Date(endDate.getTime() - i * 7 * 24 * 60 * 60 * 1000);
      const weekStart = new Date(weekEnd.getTime() - 6 * 24 * 60 * 60 * 1000);
      return { weekStart: weekStart.toISOString().split('T')[0], weekEnd: weekEnd.toISOString().split('T')[0], lent: 0, borrowed: 0, count: 0 };
    }).reverse();

    for (const t of [...quickTxns, ...mySecure]) {
      const d = new Date(t.date || t.createdAt);
      if (isNaN(d.getTime())) continue;
      for (const w of weeklyBreakdown) {
        const ws = new Date(w.weekStart);
        const we = new Date(w.weekEnd);
        if (d >= ws && d <= we) {
          if (t.role === 'lender') w.lent += t.amount || 0;
          else if (t.role === 'borrower') w.borrowed += t.amount || 0;
          w.count++;
          break;
        }
      }
    }

    // Category amount maps for comparison tab
    const catBreakdown = {};
    for (const [cat, d] of Object.entries(catMap)) catBreakdown[cat] = d.amount;
    const prevCatBreakdown = {};
    for (const [cat, d] of Object.entries(prevCatMap)) prevCatBreakdown[cat] = d.amount;

    // Human-readable period labels
    const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const fmtPeriod = (s, e) => {
      if (s.getMonth() === e.getMonth() && s.getFullYear() === e.getFullYear())
        return `${_months[s.getMonth()]} ${s.getFullYear()}`;
      if (s.getFullYear() === e.getFullYear())
        return `${_months[s.getMonth()]}–${_months[e.getMonth()]} ${e.getFullYear()}`;
      return `${_months[s.getMonth()]} ${s.getFullYear()} – ${_months[e.getMonth()]} ${e.getFullYear()}`;
    };

    // Period-over-period comparison
    const comparison = {
      current: {
        netBalance: currentLent - currentBorrowed,
        totalAmountLent: currentLent,
        totalAmountBorrowed: currentBorrowed,
        totalTransactions: currTxnCount,
        groupExpenseTotal,
        groupUserShare,
      },
      previous: {
        netBalance: prevLent - prevBorrowed,
        totalAmountLent: prevLent,
        totalAmountBorrowed: prevBorrowed,
        totalTransactions: prevTxnCount,
        groupExpenseTotal: 0,
        groupUserShare: 0,
      },
      currentLabel: fmtPeriod(startDate, endDate),
      previousLabel: fmtPeriod(prevStartDate, prevEndDate),
      categoryBreakdown: catBreakdown,
      previousCategoryBreakdown: prevCatBreakdown,
      lentChange: prevLent > 0 ? Math.round(((currentLent - prevLent) / prevLent) * 100) : null,
      borrowedChange: prevBorrowed > 0 ? Math.round(((currentBorrowed - prevBorrowed) / prevBorrowed) * 100) : null,
      txnCountChange: prevTxnCount > 0 ? Math.round(((currTxnCount - prevTxnCount) / prevTxnCount) * 100) : null,
    };

    // Cash-flow timeline — chronological events sorted by date
    const allTxnsRaw = [
      ...quickTxns.map(t => ({ date: t.date, amount: t.amount || 0, role: t.role, label: t.description || t.note || (t.role === 'lender' ? 'Lent' : 'Borrowed'), category: t.category || 'other', type: 'quick' })),
      ...mySecure.map(t => ({ date: t.createdAt, amount: t.amount || 0, role: t.role, label: t.description || t.note || (t.role === 'lender' ? 'Lent' : 'Borrowed'), category: t.category || 'other', type: 'secure' })),
    ].sort((a, b) => new Date(a.date) - new Date(b.date));

    // Running balance for cash-flow
    let runningBalance = 0;
    const cashFlow = allTxnsRaw.map(t => {
      const delta = t.role === 'lender' ? t.amount : -t.amount;
      runningBalance += delta;
      return {
        date: t.date,
        label: t.label,
        amount: t.amount,
        delta,
        balance: Math.round(runningBalance),
        category: t.category,
        type: t.type,
      };
    });

    // Subcategory simulation: split top categories by day-of-week / note keyword
    const subCategoryMap = {};
    for (const t of [...quickTxns, ...mySecure]) {
      const cat = (t.category || 'other').toLowerCase();
      const note = (t.description || t.note || '').toLowerCase();
      let sub = 'General';
      if (note.includes('restaurant') || note.includes('dining')) sub = 'Restaurants';
      else if (note.includes('grocery') || note.includes('supermarket') || note.includes('kirana')) sub = 'Groceries';
      else if (note.includes('snack') || note.includes('cafe') || note.includes('coffee')) sub = 'Snacks & Café';
      else if (note.includes('uber') || note.includes('ola') || note.includes('cab') || note.includes('taxi')) sub = 'Cab';
      else if (note.includes('petrol') || note.includes('fuel') || note.includes('diesel')) sub = 'Fuel';
      else if (note.includes('rent') || note.includes('flat')) sub = 'Rent';
      else if (note.includes('amazon') || note.includes('flipkart') || note.includes('online')) sub = 'Online Shopping';
      else if (note.includes('cloth') || note.includes('shirt') || note.includes('dress')) sub = 'Clothing';
      if (!subCategoryMap[cat]) subCategoryMap[cat] = {};
      if (!subCategoryMap[cat][sub]) subCategoryMap[cat][sub] = { amount: 0, count: 0 };
      subCategoryMap[cat][sub].amount += t.amount || 0;
      subCategoryMap[cat][sub].count++;
    }
    const subCategories = {};
    for (const [cat, subs] of Object.entries(subCategoryMap)) {
      subCategories[cat] = Object.entries(subs)
        .map(([sub, d]) => ({ sub, amount: Math.round(d.amount), count: d.count }))
        .sort((a, b) => b.amount - a.amount);
    }

    res.json({
      period: { startDate, endDate },
      overview: {
        totalTransactions: currTxnCount + groupExpenses.length,
        totalAmountLent: currentLent,
        totalAmountBorrowed: currentBorrowed,
        netBalance: currentLent - currentBorrowed,
        groupExpenseTotal,
        groupUserShare,
        clearedTransactions: quickCleared + secureCleared,
        unclearedTransactions: (quickTxns.length - quickCleared) + (mySecure.length - secureCleared),
        pendingCount,
        pendingAmount,
      },
      byType: {
        quick: { count: quickTxns.length, amountLent: quickLent, amountBorrowed: quickBorrowed, cleared: quickCleared },
        secure: { count: mySecure.length, amountLent: secureLent, amountBorrowed: secureBorrowed, cleared: secureCleared },
        group: { count: groupExpenses.length, totalExpenses: groupExpenseTotal, yourShare: groupUserShare },
      },
      advanced: {
        highestTxn,
        lowestTxn,
        avgTxn: Math.round(avgTxn),
        avgDailySpend: Math.round(avgDailySpend),
        daysInPeriod,
      },
      comparison,
      categories,
      monthlyTrend: months,
      weeklyBreakdown,
      topCounterparties,
      groupBreakdown,
      dailySpending,
      cashFlow: cashFlow.slice(-50), // last 50 events
      subCategories,
    });
  } catch (err) {
    console.error('Reports summary error:', err);
    res.status(500).json({ message: 'Server error', detail: err.message });
  }
};
