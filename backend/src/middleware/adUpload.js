const multer = require('multer');
const os = require('os');
const fs = require('fs');

const adUploadStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, os.tmpdir()),
  filename: (_req, file, cb) => {
    const safeName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, `ad-${Date.now()}-${Math.round(Math.random() * 1e9)}-${safeName}`);
  },
});

const adUpload = multer({
  storage: adUploadStorage,
  limits: { fileSize: 150 * 1024 * 1024 },
});

const handleAdUpload = (req, res, next) => {
  adUpload.single('media')(req, res, (error) => {
    const cleanupTempFile = () => {
      if (req.file?.path) fs.promises.unlink(req.file.path).catch(() => {});
    };
    if (!error) return next();
    if (error instanceof multer.MulterError) {
      cleanupTempFile();
      if (error.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ error: 'Ad media file is too large. Please upload a file smaller than 150 MB.' });
      }
      return res.status(400).json({ error: error.message || 'Failed to process ad media upload.' });
    }
    console.error('Ad upload middleware failed:', error);
    cleanupTempFile();
    return res.status(400).json({ error: error?.message || 'Failed to process ad media upload.' });
  });
};

module.exports = { handleAdUpload };
