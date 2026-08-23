module.exports = (router, { auth, upload }) => {
  const ctrl = require('../../controllers/communityController');

  router.post('/communities', auth, ctrl.createCommunity);
  router.get('/communities', auth, ctrl.getMyCommunities);
  router.post('/communities/join', auth, ctrl.joinCommunity);        // before /:id
  router.get('/communities/:id', auth, ctrl.getCommunity);
  router.patch('/communities/:id', auth, ctrl.updateCommunity);
  router.delete('/communities/:id', auth, ctrl.deleteCommunity);
  router.post('/communities/:id/groups', auth, ctrl.addGroupToCommunity);
  router.post('/communities/:id/image', auth, upload.single('image'), ctrl.uploadImage);
  router.get('/communities/:id/image', ctrl.getImage);
};
