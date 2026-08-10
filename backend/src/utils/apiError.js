class EmailServiceError extends Error {
  constructor(cause) {
    super('Email service is temporarily unavailable');
    this.name = 'EmailServiceError';
    this.cause = cause;
    this.statusCode = 503;
  }
}

function handleRouteError(res, error) {
  if (error instanceof EmailServiceError || error.name === 'EmailServiceError') {
    return res.status(503).json({
      message: 'Email service is temporarily unavailable. Please try again later.',
    });
  }
  res.status(500).json({ message: 'Internal server error' });
}

module.exports = { EmailServiceError, handleRouteError };
