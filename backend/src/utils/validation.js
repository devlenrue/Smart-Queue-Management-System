function requiredString(value, fieldName, { min = 1, max = 255 } = {}) {
  if (typeof value !== 'string') {
    throw httpError(400, `${fieldName} must be a string.`);
  }

  const trimmed = value.trim();
  if (trimmed.length < min || trimmed.length > max) {
    throw httpError(400, `${fieldName} must be between ${min} and ${max} characters.`);
  }
  return trimmed;
}

function email(value) {
  const normalized = requiredString(value, 'Email', { min: 5, max: 255 }).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) {
    throw httpError(400, 'Email must be a valid email address.');
  }
  return normalized;
}

function password(value) {
  if (typeof value !== 'string' || value.length < 6 || value.length > 128) {
    throw httpError(400, 'Password must be between 6 and 128 characters.');
  }
  return value;
}

function positiveInteger(value, fieldName) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) {
    throw httpError(400, `${fieldName} must be a positive integer.`);
  }
  return number;
}

function positiveNumber(value, fieldName) {
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0 || number > 9999) {
    throw httpError(400, `${fieldName} must be greater than 0.`);
  }
  return number;
}

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

module.exports = {
  requiredString,
  email,
  password,
  positiveInteger,
  positiveNumber,
  httpError
};
