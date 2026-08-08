/**
 * BaseRepository — wraps all Mongoose-specific calls in one place.
 *
 * Swap strategy: if you switch to a different database (PostgreSQL, Firestore,
 * etc.), create a new BaseRepository (or parallel class) that speaks the new
 * driver.  Model-specific repos extend from it; controllers never change.
 */
class BaseRepository {
  constructor(Model) {
    this.Model = Model;
  }

  findById(id, projection) {
    return this.Model.findById(id, projection);
  }

  findOne(filter, projection) {
    return this.Model.findOne(filter, projection);
  }

  find(filter = {}, options = {}) {
    const { sort, limit, skip, projection, lean = false } = options;
    let q = this.Model.find(filter, projection);
    if (sort)  q = q.sort(sort);
    if (skip)  q = q.skip(skip);
    if (limit) q = q.limit(limit);
    if (lean)  q = q.lean();
    return q;
  }

  create(data) {
    return this.Model.create(data);
  }

  updateById(id, update, options = { new: true }) {
    return this.Model.findByIdAndUpdate(id, update, options);
  }

  updateOne(filter, update, options = {}) {
    return this.Model.findOneAndUpdate(filter, update, { new: true, ...options });
  }

  updateMany(filter, update) {
    return this.Model.updateMany(filter, update);
  }

  deleteById(id) {
    return this.Model.findByIdAndDelete(id);
  }

  deleteOne(filter) {
    return this.Model.findOneAndDelete(filter);
  }

  deleteMany(filter) {
    return this.Model.deleteMany(filter);
  }

  count(filter = {}) {
    return this.Model.countDocuments(filter);
  }

  aggregate(pipeline) {
    return this.Model.aggregate(pipeline);
  }
}

module.exports = BaseRepository;
