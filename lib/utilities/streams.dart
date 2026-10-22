/// Emits [read]'s value on listen and again after every [changes] event.
Stream<T> startWith<T>(T Function() read, Stream<Object?> changes) async* {
  yield read();
  await for (final _ in changes) {
    yield read();
  }
}
