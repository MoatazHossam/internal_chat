class PageRequest { const PageRequest({this.cursor, this.limit = 30}); final String? cursor; final int limit; }
class PageResult<T> { const PageResult({required this.items, this.nextCursor}); final List<T> items; final String? nextCursor; }
