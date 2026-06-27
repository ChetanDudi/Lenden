const FraudAlert = require('../models/fraudAlert');
const { runScanAndNotify } = require('../utils/fraudAlertingScheduler');
const { logAdminAudit } = require('../utils/adminAuditLogger');

exports.listFraudAlerts = async (req, res) => {
  try {
    const { status } = req.query;
    const filter = {};
    if (status && status !== 'all') filter.status = status;
    const alerts = await FraudAlert.find(filter).sort({ createdAt: -1 });
    res.json({ alerts });
  } catch (err) {
    console.error('Error listing fraud alerts:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.updateFraudAlert = async (req, res) => {
  try {
    const { status, reviewNote } = req.body;
    if (!['reviewing', 'resolved', 'dismissed'].includes(status)) {
      return res.status(400).json({ error: 'Invalid status.' });
    }

    const alert = await FraudAlert.findById(req.params.id);
    if (!alert) return res.status(404).json({ error: 'Fraud alert not found' });

    alert.status = status;
    if (reviewNote !== undefined) alert.reviewNote = reviewNote;
    alert.reviewedBy = req.user._id;
    await alert.save();

    await logAdminAudit({
      req,
      admin: req.user,
      action: 'fraud_alert_updated',
      targetType: 'fraudAlert',
      targetId: alert._id,
      summary: `Fraud alert ${alert._id} marked as ${status}`,
      details: { reviewNote },
    });

    res.json({ message: 'Fraud alert updated.', alert });
  } catch (err) {
    console.error('Error updating fraud alert:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.triggerFraudScan = async (req, res) => {
  try {
    const newAlerts = await runScanAndNotify();
    res.json({ message: `Scan complete. ${newAlerts.length} new alert(s) found.`, newAlerts });
  } catch (err) {
    console.error('Error running manual fraud scan:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
