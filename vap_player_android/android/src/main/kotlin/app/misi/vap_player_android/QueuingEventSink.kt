package app.misi.vap_player_android

/**
 * An event sink that queues events until a downstream delegate attaches,
 * so events emitted before Dart subscribes are not lost.
 */
class QueuingEventSink<T> {
    private var delegate: PigeonEventSink<T>? = null
    private val eventQueue = ArrayList<Any>()
    private var done = false

    private class EndOfStreamEvent

    fun setDelegate(delegate: PigeonEventSink<T>?) {
        this.delegate = delegate
        maybeFlush()
    }

    fun endOfStream() {
        enqueue(EndOfStreamEvent())
        maybeFlush()
        done = true
    }

    fun success(event: T) {
        enqueue(event as Any)
        maybeFlush()
    }

    private fun enqueue(event: Any) {
        if (done) return
        eventQueue.add(event)
    }

    private fun maybeFlush() {
        val delegate = this.delegate ?: return
        for (event in eventQueue) {
            if (event is EndOfStreamEvent) {
                delegate.endOfStream()
            } else {
                @Suppress("UNCHECKED_CAST")
                delegate.success(event as T)
            }
        }
        eventQueue.clear()
    }
}
