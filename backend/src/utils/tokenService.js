const jwt = require('jsonwebtoken');
const RefreshToken = require('../models/refreshToken');
const crypto = require('crypto');

const ACCESS_TOKEN_EXPIRY = '15m'; // 15 minutes
const REFRESH_TOKEN_EXPIRY = '7d'; // 7 days

class TokenService {
  static generateAccessToken(payload) {
    if (!process.env.JWT_SECRET) {
      throw new Error('JWT_SECRET environment variable is not set');
    }
    return jwt.sign(payload, process.env.JWT_SECRET, { expiresIn: ACCESS_TOKEN_EXPIRY });
  }

  static generateRefreshToken() {
    return crypto.randomBytes(64).toString('hex');
  }

  static async saveRefreshToken(tokenData) {
    const refreshToken = new RefreshToken({
      token: tokenData.token,
      userId: tokenData.userId,
      userType: tokenData.userType,
      deviceId: tokenData.deviceId,
      deviceName: tokenData.deviceName,
      ipAddress: tokenData.ipAddress,
      userAgent: tokenData.userAgent,
      expiresAt: tokenData.expiresAt
    });

    await refreshToken.save();
    return refreshToken;
  }

  static async validateRefreshToken(token) {
    const refreshToken = await RefreshToken.findOne({
      token,
      isRevoked: false,
      expiresAt: { $gt: new Date() }
    });

    if (!refreshToken) {
      return null;
    }

    // Update last used timestamp
    refreshToken.lastUsed = new Date();
    await refreshToken.save();

    return refreshToken;
  }

  static async revokeRefreshToken(token) {
    await RefreshToken.findOneAndUpdate(
      { token },
      { isRevoked: true }
    );
  }

  static async revokeAllUserTokens(userId, userType, deviceId = null) {
    const query = { userId, userType, isRevoked: false };
    if (deviceId) {
      query.deviceId = deviceId;
    }

    await RefreshToken.updateMany(query, { isRevoked: true });
  }

  static async cleanupExpiredTokens() {
    await RefreshToken.deleteMany({
      expiresAt: { $lt: new Date() }
    });
  }

  static async getUserActiveTokens(userId, userType) {
    return await RefreshToken.find({
      userId,
      userType,
      isRevoked: false,
      expiresAt: { $gt: new Date() }
    }).sort({ createdAt: -1 });
  }

  static calculateTokenExpiry() {
    const expiryDate = new Date();
    expiryDate.setDate(expiryDate.getDate() + 7); // 7 days from now
    return expiryDate;
  }
}

module.exports = TokenService;
