const _kDefaultCommunityImage =
    'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=800&fit=crop&auto=format';

const _kCategoryImages = <String, List<String>>{
  'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&fit=crop&auto=format':
      ['spirit', 'reiki', 'heal', 'meditat', 'yoga', 'chakra', 'zen', 'mantra', 'divine', 'cosmic'],
  'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&fit=crop&auto=format':
      ['art', 'craft', 'paint', 'design', 'creat', 'draw', 'sculpt', 'sketch', 'illust'],
  'https://images.unsplash.com/photo-1621416894569-0f39ed31d247?w=800&fit=crop&auto=format':
      ['crypto', 'bitcoin', 'invest', 'finance', 'stock', 'trade', 'nft', 'web3', 'defi', 'forex'],
  'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&fit=crop&auto=format':
      ['fit', 'gym', 'sport', 'workout', 'run', 'muscle', 'athlet', 'crossfit', 'cardio'],
  'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&fit=crop&auto=format':
      ['food', 'cook', 'recipe', 'kitchen', 'bake', 'chef', 'cuisine', 'meal', 'diet'],
  'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=800&fit=crop&auto=format':
      ['travel', 'trip', 'adventur', 'journey', 'tour', 'wander', 'backpack', 'explore', 'trek'],
  'https://images.unsplash.com/photo-1511379938547-c1f69419868d?w=800&fit=crop&auto=format':
      ['music', 'band', 'song', 'concert', 'guitar', 'sing', 'melody', 'playlist', 'album'],
  'https://images.unsplash.com/photo-1517694712202-14dd9538aa97?w=800&fit=crop&auto=format':
      ['tech', 'code', 'program', 'dev', 'software', 'hack', 'data', 'ai', 'ml', 'cyber'],
  'https://images.unsplash.com/photo-1567954970774-58d6aa6c50dc?w=800&fit=crop&auto=format':
      ['crystal', 'gem', 'stone', 'mineral', 'quartz', 'tarot'],
  'https://images.unsplash.com/photo-1511895426328-dc8714191011?w=800&fit=crop&auto=format':
      ['family', 'home', 'parent', 'child', 'baby', 'mom', 'dad', 'sibling'],
  'https://images.unsplash.com/photo-1497366216548-37526070297c?w=800&fit=crop&auto=format':
      ['business', 'office', 'work', 'career', 'professional', 'entrepreneur', 'startup'],
  'https://images.unsplash.com/photo-1524178232363-1fb2b075b655?w=800&fit=crop&auto=format':
      ['study', 'learn', 'educat', 'student', 'college', 'school', 'class', 'academic'],
  'https://images.unsplash.com/photo-1535268647677-300dbf3d78d1?w=800&fit=crop&auto=format':
      ['pet', 'animal', 'dog', 'cat', 'bird', 'wildlife'],
};

/// Returns a stable Unsplash image URL for a community based on keyword matching in its name.
String defaultCommunityImageUrl(String communityName) {
  final n = communityName.toLowerCase();
  for (final entry in _kCategoryImages.entries) {
    if (entry.value.any((k) => n.contains(k))) return entry.key;
  }
  return _kDefaultCommunityImage;
}

/// Keyword-based lookup for groups.
/// Returns '' when no keyword matches (callers should show a local placeholder).
String defaultGroupImageUrl(String groupTitle) {
  final n = groupTitle.toLowerCase();
  for (final entry in _kCategoryImages.entries) {
    if (entry.value.any((k) => n.contains(k))) return entry.key;
  }
  return '';
}
