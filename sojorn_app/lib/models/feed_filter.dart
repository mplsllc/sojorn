/// Filter options for the home feed
enum FeedFilter {
  all('All Posts', null),
  posts('Posts Only', 'post'),
  quips('Quips Only', 'quip'),
  chains('Chains Only', 'chain'),
  beacons('Beacons Only', 'beacon');

  final String label;
  final String? typeValue;

  const FeedFilter(this.label, this.typeValue);
}
