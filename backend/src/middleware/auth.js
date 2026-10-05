const jwt = require('jsonwebtoken');

function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ message: 'A Bearer token is required.' });
  }

  try {
    req.user = jwt.verify(token, process.env.JWT_SECRET || 'development-only-secret');
    return next();
  } catch (error) {
    return res.status(401).json({ message: 'The token is invalid or has expired.' });
  }
}

function authorize(...allowedRoles) {
  return (req, res, next) => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ message: 'You do not have permission to perform this action.' });
    }
    return next();
  };
}

module.exports = { authenticate, authorize };
