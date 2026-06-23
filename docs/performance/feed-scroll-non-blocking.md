# Feed scroll — keeping the main thread free

## Symptom

On real (large) photo libraries, scrolling the vertical feed (`FeedScreen`)
occasionally froze for a moment, even though images loaded fine. The freeze got
worse the more the user had already sorted.

## Root cause

Every photo that scrolls off-screen without an explicit decision is treated as
*kept* (`FeedScreen.handleDisappear` → `SortingSession.recordKeep`). That path
ends in `SortingSession.persist()`, which wrote the **entire** `sortedIDs` set to
`UserDefaults` synchronously on the main thread.

`sortedIDs` is cumulative across **all** sessions and persisted, so with real
usage it grows to thousands of identifiers. Serializing that array (property-list
encoding inside `UserDefaults.set`) on every single scroll transition dropped
frames — hence intermittent freezes that worsen as the index grows.

The image pipeline itself was **not** the cause: `PhotoLibrary.image(...)` is
`await`-ed off the main thread, and `ImagePrefetcher` uses
`PHCachingImageManager`, which decodes on its own background queues.

## Fix

`persist()` now snapshots the IDs on the main actor (a cheap reference copy) and
performs the encode + write on a dedicated `qos: .utility` serial queue. The main
thread never pays for the serialization, regardless of how fast the user swipes.

```swift
private let persistQueue = DispatchQueue(label: "com.tabularium.sorting.persist", qos: .utility)

private func persist() {
    let snapshot = Array(sortedIDs)
    let key = Self.sortedKey
    persistQueue.async {
        UserDefaults.standard.set(snapshot, forKey: key)
    }
}
```

Debouncing was considered and rejected: a delayed flush can still land on the
main thread mid-swipe, so the user would still feel it. Off-loading the work
entirely avoids that.

## Caveat

Writes are now asynchronous. `UserDefaults` keeps its in-memory representation up
to date and flushes on its own, but a write dispatched microseconds before the
app is force-killed could be lost. The risk window is tiny and the data
(already-sorted IDs) is non-critical — at worst a handful of photos are
re-proposed. If this ever matters, flush on `scenePhase` → `.background`.
