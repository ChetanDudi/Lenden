const BaseRepository = require('./BaseRepository');
const User = require('../models/user');

class UserRepository extends BaseRepository {
  constructor() {
    super(User);
  }

  findByEmail(email, projection) {
    return this.findOne({ email }, projection);
  }

  findByUsername(username, projection) {
    return this.findOne({ username }, projection);
  }

  findByReferralCode(code) {
    return this.findOne({ referralCode: code });
  }

  findByGoogleId(googleId) {
    return this.findOne({ googleId });
  }

  isEmailTaken(email) {
    return this.count({ email }).then(n => n > 0);
  }

  isUsernameTaken(username) {
    return this.count({ username }).then(n => n > 0);
  }
}

module.exports = new UserRepository();
