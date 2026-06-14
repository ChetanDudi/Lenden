const SupportQuery = require('../models/supportQuery');
const Activity = require('../models/activity');
const User = require('../models/user');
const Admin = require('../models/admin');
const { logAdminAudit } = require('../utils/adminAuditLogger');

const escapeRegex = (value = '') => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const ADMIN_PERMISSION_DEFAULTS = {
  canManageUsers: true,
  canManageTransactions: true,
  canManageSupport: true,
  canManageContent: true,
  canManageDigitise: true,
  canManageSettings: true,
  canViewAuditLogs: true,
};

const normalizePermissions = (permissions = {}) => {
  const normalized = {};
  for (const [key, value] of Object.entries(ADMIN_PERMISSION_DEFAULTS)) {
    normalized[key] = permissions[key] !== false ? value : false;
  }
  return normalized;
};

const hasSupportPermission = (admin) =>
  !!admin &&
  (admin.isSuperAdmin === true ||
    normalizePermissions(admin.permissions || {}).canManageSupport === true);

const getSlaHours = (priority = 'normal') => {
  switch ((priority || 'normal').toString()) {
    case 'critical':
      return 2;
    case 'high':
      return 8;
    case 'low':
      return 48;
    default:
      return 24;
  }
};

const mapSupportQuery = (query) => {
  const item = query.toObject ? query.toObject() : query;
  const baseTime = item.lastAdminReplyAt || item.createdAt;
  const slaHours = getSlaHours(item.priority);
  const overdue =
    ['open', 'in_progress'].includes(item.status) &&
    baseTime &&
    Date.now() - new Date(baseTime).getTime() > slaHours * 60 * 60 * 1000;

  return {
    ...item,
    slaHours,
    isOverdue: overdue,
  };
};

const getCurrentAdmin = async (req) => {
  const adminId = req.user?._id || req.user?.userId || req.user?.id;
  if (adminId) {
    const byId = await Admin.findById(adminId).select('-password');
    if (byId) return byId;
  }
  if (req.user?.email) {
    return Admin.findOne({ email: req.user.email }).select('-password');
  }
  return null;
};

const escapeCsv = (value) => `"${String(value ?? '').replace(/"/g, '""')}"`;

// Helper: Delete queries older than 7 days
const deleteOldQueries = async () => {
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const oldQueries = await SupportQuery.find({ createdAt: { $lt: sevenDaysAgo } });
  for (const query of oldQueries) {
    await query.deleteOne();
    io.emit('support_query_deleted', { queryId: query._id });
  }
};

module.exports = (io) => {
  // User creates a new support query
  const createSupportQuery = async (req, res) => {
    try {
      await deleteOldQueries();
      const { topic, description } = req.body;
      const userId = req.user._id; // Assuming user ID is available from auth middleware

      const newQuery = new SupportQuery({
        user: userId,
        topic,
        description,
      });

      await newQuery.save();

      // Populate user details for the emitted event
      const populatedQuery = await newQuery.populate('user', 'username email');

      // Emit Socket.IO event for new query
      io.emit('support_query_created', populatedQuery);
      io.to(`query_${newQuery._id}`).emit('support_query_updated', populatedQuery);

      // Log activity
      await Activity.create({
        user: userId,
        type: 'support_query_created',
        title: `Support query created: ${topic}`,
        description: `User submitted a new support query with topic: ${topic}.`,
        metadata: { queryId: newQuery._id, topic, description },
      });

      res.status(201).json({ message: 'Support query created successfully', query: populatedQuery });
    } catch (error) {
      console.error('Backend: createSupportQuery - Error', error);
      res.status(500).json({ error: 'Failed to create support query' });
    }
  };

  // User views their own support queries
  const getUserSupportQueries = async (req, res) => {
    try {
      await deleteOldQueries();
      const userId = req.user._id;
      const queries = await SupportQuery.find({ user: userId }).sort({ createdAt: -1 });
      res.status(200).json({ queries });
    } catch (error) {
      console.error('Backend: getUserSupportQueries - Error', error);
      res.status(500).json({ error: 'Failed to fetch user support queries' });
    }
  };

  // User updates their own support query (only if no admin reply yet)
  const updateSupportQuery = async (req, res) => {
    try {
      await deleteOldQueries();
      const { queryId } = req.params;
      const { topic, description } = req.body;
      const userId = req.user._id;

      const query = await SupportQuery.findOne({ _id: queryId, user: userId });

      if (!query) {
        return res.status(404).json({ error: 'Support query not found or you do not have permission to edit it' });
      }

      if (query.replies && query.replies.length > 0) {
        return res.status(403).json({ error: 'Cannot edit query after an admin has replied' });
      }

      query.topic = topic || query.topic;
      query.description = description || query.description;
      await query.save();

      // Populate user details for the emitted event
      const populatedQuery = await query.populate('user', 'username email');

      // Emit Socket.IO event for updated query
      io.emit('support_query_updated', populatedQuery);
      io.to(`query_${query._id}`).emit('support_query_updated', populatedQuery);

      // Log activity
      await Activity.create({
        user: userId,
        type: 'support_query_updated',
        title: `Support query updated: ${query.topic}`,
        description: `User updated their support query with ID: ${queryId}.`,
        metadata: { queryId: query._id, newTopic: topic, newDescription: description },
      });

      res.status(200).json({ message: 'Support query updated successfully', query: populatedQuery });
    } catch (error) {
      console.error('Backend: updateSupportQuery - Error', error);
      res.status(500).json({ error: 'Failed to update support query' });
    }
  };

  // Admin views all support queries
  const getAllSupportQueries = async (req, res) => {
    try {
      await deleteOldQueries();
      const currentAdmin = await getCurrentAdmin(req);
      if (!hasSupportPermission(currentAdmin)) {
        return res.status(403).json({ error: 'You do not have permission to manage support queries' });
      }

      const { searchTerm, status, priority, assigned } = req.query; // Search by topic
      let query = {};

      if (searchTerm) {
        const safeSearch = escapeRegex(searchTerm.toString().trim());
        query.$or = [
          { topic: { $regex: safeSearch, $options: 'i' } },
          { description: { $regex: safeSearch, $options: 'i' } },
        ];
      }

      if (status && status !== 'all') {
        query.status = status;
      }

      if (priority && priority !== 'all') {
        query.priority = priority;
      }

      if (assigned === 'mine' && currentAdmin?._id) {
        query.assignedAdmin = currentAdmin._id;
      } else if (assigned === 'unassigned') {
        query.assignedAdmin = null;
      }

      const queries = await SupportQuery.find(query)
        .populate('user', 'username email') // Populate user details
        .populate('replies.admin', 'username email') // Populate admin details for replies
        .populate('assignedAdmin', 'username email name')
        .populate('internalNotes.admin', 'email name')
        .sort({ createdAt: -1 });

      const mappedQueries = queries.map(mapSupportQuery);
      const summary = {
        total: mappedQueries.length,
        open: mappedQueries.filter((item) => item.status === 'open').length,
        inProgress: mappedQueries.filter((item) => item.status === 'in_progress').length,
        resolved: mappedQueries.filter((item) => item.status === 'resolved').length,
        critical: mappedQueries.filter((item) => item.priority === 'critical').length,
        assignedToMe: mappedQueries.filter(
          (item) =>
            item.assignedAdmin &&
            item.assignedAdmin._id &&
            item.assignedAdmin._id.toString() === currentAdmin?._id?.toString()
        ).length,
        overdue: mappedQueries.filter((item) => item.isOverdue).length,
      };

      res.status(200).json({
        queries: mappedQueries,
        summary,
        currentAdmin: currentAdmin
          ? {
              _id: currentAdmin._id,
              email: currentAdmin.email,
              isSuperAdmin: currentAdmin.isSuperAdmin === true,
              permissions: normalizePermissions(currentAdmin.permissions || {}),
            }
          : null,
      });
    } catch (error) {
      console.error('Backend: getAllSupportQueries - Error', error);
      res.status(500).json({ error: 'Failed to fetch all support queries' });
    }
  };

  // Admin adds a reply to a support query
  const replyToSupportQuery = async (req, res) => {
    try {
      const { queryId } = req.params;
      const { replyText } = req.body;
      const currentAdmin = await getCurrentAdmin(req);
      if (!hasSupportPermission(currentAdmin)) {
        return res.status(403).json({ error: 'You do not have permission to reply to support queries' });
      }
      const adminId = currentAdmin._id;

      const query = await SupportQuery.findById(queryId);

      if (!query) {
        return res.status(404).json({ error: 'Support query not found' });
      }

      query.replies.push({ admin: adminId, replyText });
      query.status = 'in_progress'; // Automatically set status to in_progress
      if (!query.firstAdminReplyAt) {
        query.firstAdminReplyAt = new Date();
      }
      query.lastAdminReplyAt = new Date();
      if (!query.assignedAdmin) {
        query.assignedAdmin = adminId;
      }
      await query.save();

      // Re-fetch the query and populate it for emission
      const populatedQuery = await SupportQuery.findById(queryId)
        .populate('user', 'username email')
        .populate('replies.admin', 'username email')
        .populate('assignedAdmin', 'username email name')
        .populate('internalNotes.admin', 'email name');

      // Emit Socket.IO event for updated query with new reply
      io.emit('support_query_updated', populatedQuery);
      io.to(`query_${query._id}`).emit('support_query_updated', populatedQuery);

      // Log activity for the user whose query was replied to
      await Activity.create({
        user: query.user, // The user who created the query
        type: 'support_query_replied',
        title: `Admin replied to your query: ${query.topic}`,
        description: `An admin has replied to your support query with ID: ${queryId}.`,
        metadata: { queryId: query._id, adminId, replyText },
      });

      await logAdminAudit({
        req,
        admin: currentAdmin,
        action: 'support_replied',
        targetType: 'support_query',
        targetId: query._id,
        summary: `${currentAdmin.email} replied to support query "${query.topic}"`,
        details: { replyText },
      });

      res.status(200).json({ message: 'Reply added successfully', query: populatedQuery });
    } catch (error) {
      console.error('Backend: replyToSupportQuery - Error', error);
      res.status(500).json({ error: 'Failed to add reply' });
    }
  };

  // Admin edits a specific reply
  const editReply = async (req, res) => {
    try {
      const { queryId, replyId } = req.params;
      const { replyText } = req.body;
      const currentAdmin = await getCurrentAdmin(req);
      if (!hasSupportPermission(currentAdmin)) {
        return res.status(403).json({ error: 'You do not have permission to edit support replies' });
      }
      const adminId = currentAdmin._id;

      const query = await SupportQuery.findById(queryId);

      if (!query) {
        return res.status(404).json({ error: 'Support query not found' });
      }

      const reply = query.replies.id(replyId);

      if (!reply) {
        return res.status(404).json({ error: 'Reply not found' });
      }

      // Optional: Check if the admin editing is the one who created the reply
      // if (reply.admin.toString() !== adminId.toString()) {
      //   return res.status(403).json({ error: 'You can only edit your own replies' });
      // }

      reply.replyText = replyText;
      query.lastAdminReplyAt = new Date();
      await query.save();

      // Populate the query and the edited reply for emission
      const populatedQuery = await query
        .populate('user', 'username email')
        .populate('replies.admin', 'username email')
        .populate('assignedAdmin', 'username email name')
        .populate('internalNotes.admin', 'email name');

      // Emit Socket.IO event for updated query with edited reply
      io.emit('support_query_updated', populatedQuery);
      io.to(`query_${query._id}`).emit('support_query_updated', populatedQuery);

      // Log activity for the user whose query's reply was edited
      await Activity.create({
        user: query.user,
        type: 'support_reply_edited',
        title: `Admin edited a reply to your query: ${query.topic}`,
        description: `An admin edited a reply to your support query with ID: ${queryId}.`,
        metadata: { queryId: query._id, replyId, newReplyText: replyText },
      });

      await logAdminAudit({
        req,
        admin: currentAdmin,
        action: 'support_reply_edited',
        targetType: 'support_query',
        targetId: query._id,
        summary: `${currentAdmin.email} edited a support reply on "${query.topic}"`,
        details: { replyId },
      });

      res.status(200).json({ message: 'Reply updated successfully', query: populatedQuery });
    } catch (error) {
      res.status(500).json({ error: 'Failed to update reply' });
    }
  };

  // Admin deletes a specific reply
  const deleteReply = async (req, res) => {
    try {
      const { queryId, replyId } = req.params;
      const currentAdmin = await getCurrentAdmin(req);
      if (!hasSupportPermission(currentAdmin)) {
        return res.status(403).json({ error: 'You do not have permission to delete support replies' });
      }

      const query = await SupportQuery.findById(queryId);

      if (!query) {
        return res.status(404).json({ error: 'Support query not found' });
      }

      query.replies.id(replyId).remove();
      await query.save();

      // Populate the query for emission after reply deletion
      const populatedQuery = await query
        .populate('user', 'username email')
        .populate('replies.admin', 'username email')
        .populate('assignedAdmin', 'username email name')
        .populate('internalNotes.admin', 'email name');

      // Emit Socket.IO event for updated query after reply deletion
      io.emit('support_query_updated', populatedQuery);
      io.to(`query_${query._id}`).emit('support_query_updated', populatedQuery);

      // Log activity for the user whose query's reply was deleted
      await Activity.create({
        user: query.user,
        type: 'support_reply_deleted',
        title: `Admin deleted a reply to your query: ${query.topic}`,
        description: `An admin deleted a reply to your support query with ID: ${queryId}.`,
        metadata: { queryId: query._id, replyId },
      });

      await logAdminAudit({
        req,
        admin: currentAdmin,
        action: 'support_reply_deleted',
        targetType: 'support_query',
        targetId: query._id,
        summary: `${currentAdmin.email} deleted a support reply on "${query.topic}"`,
        details: { replyId },
        severity: 'warning',
      });

      res.status(200).json({ message: 'Reply deleted successfully', query: populatedQuery });
    } catch (error) {
      res.status(500).json({ error: 'Failed to delete reply' });
    }
  };

  // Admin updates the status of a support query
  const updateQueryStatus = async (req, res) => {
    try {
      const { queryId } = req.params;
      const { status } = req.body;
      const currentAdmin = await getCurrentAdmin(req);
      if (!hasSupportPermission(currentAdmin)) {
        return res.status(403).json({ error: 'You do not have permission to update support status' });
      }
      const adminId = currentAdmin._id;

      if (!['open', 'in_progress', 'resolved', 'closed'].includes(status)) {
        return res.status(400).json({ error: 'Invalid status provided' });
      }

      const query = await SupportQuery.findById(queryId);

      if (!query) {
        return res.status(404).json({ error: 'Support query not found' });
      }

      query.status = status;
      if (status === 'resolved') {
        query.resolvedAt = new Date();
      } else if (status !== 'closed') {
        query.resolvedAt = null;
      }
      await query.save();

      // Populate the query for emission after status update
      const populatedQuery = await SupportQuery.findById(query._id)
        .populate('user', 'username email')
        .populate('replies.admin', 'username email')
        .populate('assignedAdmin', 'username email name')
        .populate('internalNotes.admin', 'email name');

      // Emit Socket.IO event for updated query after status change
      io.emit('support_query_updated', populatedQuery);
      io.to(`query_${query._id}`).emit('support_query_updated', populatedQuery);

      // Log activity for the user whose query's status was updated
      await Activity.create({
        user: query.user,
        type: 'support_query_status_updated',
        title: `Your query status updated to: ${status}`,
        description: `The status of your support query (ID: ${queryId}) has been updated to ${status}.`,
        metadata: { queryId: query._id, newStatus: status },
      });

      await logAdminAudit({
        req,
        admin: currentAdmin,
        action: 'support_status_updated',
        targetType: 'support_query',
        targetId: query._id,
        summary: `${currentAdmin.email} updated support status to ${status} for "${query.topic}"`,
        details: { status },
      });

      res.status(200).json({ message: 'Query status updated successfully', query: populatedQuery });
    } catch (error) {
      res.status(500).json({ error: 'Failed to update query status' });
    }
  };

  const updateQueryWorkflow = async (req, res) => {
    try {
      const currentAdmin = await getCurrentAdmin(req);
      if (!hasSupportPermission(currentAdmin)) {
        return res.status(403).json({ error: 'You do not have permission to manage support workflow' });
      }

      const { queryId } = req.params;
      const { priority, assignedAdminId, internalNote } = req.body;
      const query = await SupportQuery.findById(queryId);

      if (!query) {
        return res.status(404).json({ error: 'Support query not found' });
      }

      if (priority && ['low', 'normal', 'high', 'critical'].includes(priority)) {
        query.priority = priority;
      }

      if (Object.prototype.hasOwnProperty.call(req.body, 'assignedAdminId')) {
        query.assignedAdmin = assignedAdminId || null;
      }

      if (internalNote && internalNote.toString().trim()) {
        query.internalNotes.push({
          admin: currentAdmin._id,
          noteText: internalNote.toString().trim(),
        });
      }

      if (query.status === 'resolved' && !query.resolvedAt) {
        query.resolvedAt = new Date();
      }

      await query.save();

      const populatedQuery = await SupportQuery.findById(queryId)
        .populate('user', 'username email')
        .populate('replies.admin', 'username email')
        .populate('assignedAdmin', 'username email name')
        .populate('internalNotes.admin', 'email name');

      io.emit('support_query_updated', populatedQuery);
      io.to(`query_${query._id}`).emit('support_query_updated', populatedQuery);

      await logAdminAudit({
        req,
        admin: currentAdmin,
        action: 'support_workflow_updated',
        targetType: 'support_query',
        targetId: query._id,
        summary: `${currentAdmin.email} updated workflow settings for support query "${query.topic}"`,
        details: {
          priority: query.priority,
          assignedAdminId: query.assignedAdmin?.toString?.() || '',
          internalNoteAdded: !!internalNote,
        },
      });

      res.status(200).json({ message: 'Support workflow updated successfully', query: populatedQuery });
    } catch (error) {
      console.error('Backend: updateQueryWorkflow - Error', error);
      res.status(500).json({ error: 'Failed to update support workflow' });
    }
  };

  const exportSupportQueries = async (req, res) => {
    try {
      const currentAdmin = await getCurrentAdmin(req);
      if (!hasSupportPermission(currentAdmin)) {
        return res.status(403).json({ error: 'You do not have permission to export support queries' });
      }

      const queries = await SupportQuery.find({})
        .populate('user', 'email username')
        .populate('assignedAdmin', 'email')
        .sort({ createdAt: -1 })
        .lean();

      await logAdminAudit({
        req,
        admin: currentAdmin,
        action: 'support_queries_exported',
        targetType: 'support_query_export',
        targetId: '',
        summary: `${currentAdmin.email} exported ${queries.length} support queries`,
      });

      const columns = [
        'Topic',
        'User Email',
        'Status',
        'Priority',
        'Assigned Admin',
        'Replies',
        'Created At',
      ];
      const csv = [
        columns.map(escapeCsv).join(','),
        ...queries.map((query) =>
          [
            query.topic,
            query.user?.email || query.user?.username || '',
            query.status,
            query.priority || 'normal',
            query.assignedAdmin?.email || '',
            (query.replies || []).length,
            query.createdAt ? new Date(query.createdAt).toISOString() : '',
          ]
            .map(escapeCsv)
            .join(',')
        ),
      ].join('\n');

      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader(
        'Content-Disposition',
        `attachment; filename="support-queries-${Date.now()}.csv"`
      );
      return res.status(200).send(csv);
    } catch (error) {
      console.error('Backend: exportSupportQueries - Error', error);
      res.status(500).json({ error: 'Failed to export support queries' });
    }
  };

  const deleteSupportQuery = async (req, res) => {
    try {
      const { queryId } = req.params;
      const userId = req.user._id;

      const query = await SupportQuery.findOne({ _id: queryId, user: userId });

      if (!query) {
        return res.status(404).json({ error: 'Support query not found or you do not have permission to delete it' });
      }

      await query.deleteOne(); // Changed from query.remove()

      io.emit('support_query_deleted', { queryId });

      await Activity.create({
        user: userId,
        type: 'support_query_deleted',
        title: `Support query deleted: ${query.topic}`,
        description: `User deleted their support query with ID: ${queryId}.`,
        metadata: { queryId: query._id },
      });

      res.status(200).json({ message: 'Support query deleted successfully' });
    } catch (error) {
      console.error('Backend: deleteSupportQuery - Error', error);
      res.status(500).json({ error: 'Failed to delete support query' });
    }
  };

  return {
    createSupportQuery,
    getUserSupportQueries,
    updateSupportQuery,
    deleteSupportQuery,
    getAllSupportQueries,
    replyToSupportQuery,
    editReply,
    deleteReply,
    updateQueryStatus,
    updateQueryWorkflow,
    exportSupportQueries,
  };
};
