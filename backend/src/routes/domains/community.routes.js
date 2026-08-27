module.exports = (router, { auth, upload }) => {
  const ctrl = require('../../controllers/communityController');

  router.post('/communities', auth, ctrl.createCommunity);
  router.get('/communities', auth, ctrl.getMyCommunities);
  router.post('/communities/join', auth, ctrl.joinCommunity);        // before /:id
  router.get('/communities/my-invites', auth, ctrl.getMyInvites);   // before /:id
  router.get('/communities/limit-info', auth, ctrl.getLimitInfo);   // before /:id
  router.get('/communities/feed', auth, ctrl.getFeed);              // before /:id
  router.get('/communities/:id', auth, ctrl.getCommunity);
  router.patch('/communities/:id', auth, ctrl.updateCommunity);
  router.delete('/communities/:id', auth, ctrl.deleteCommunity);
  router.post('/communities/:id/members', auth, ctrl.addMember);
  router.delete('/communities/:id/members', auth, ctrl.removeMembersBulk);
  router.delete('/communities/:id/members/:userId', auth, ctrl.removeMember);
  router.patch('/communities/:id/members/:userId/role', auth, ctrl.changeMemberRole);
  router.post('/communities/:id/invite/regenerate', auth, ctrl.regenerateInviteCode);
  router.post('/communities/:id/invites/accept', auth, ctrl.acceptInvite);
  router.delete('/communities/:id/invites/decline', auth, ctrl.declineInvite);
  router.post('/communities/:id/groups', auth, ctrl.addGroupToCommunity);
  router.delete('/communities/:id/groups/:groupId', auth, ctrl.removeGroupFromCommunity);
  router.get('/communities/:id/balance', auth, ctrl.getCommunityBalance);
  router.post('/communities/:id/image', auth, upload.single('image'), ctrl.uploadImage);
  router.get('/communities/:id/image', ctrl.getImage);
  router.post('/communities/:id/posts', auth, ctrl.createPost);
  router.get('/communities/:id/posts', auth, ctrl.getPosts);
  router.patch('/communities/:id/posts/:postId', auth, ctrl.updatePost);
  router.delete('/communities/:id/posts/:postId', auth, ctrl.deletePost);
  router.post('/communities/:id/posts/:postId/vote', auth, ctrl.votePoll);
  router.post('/communities/:id/posts/:postId/like', auth, ctrl.likePost);
  router.post('/communities/:id/posts/:postId/comments', auth, ctrl.addComment);
  router.delete('/communities/:id/posts/:postId/comments/:commentId', auth, ctrl.deleteComment);
};
