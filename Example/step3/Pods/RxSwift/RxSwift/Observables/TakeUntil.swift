//
//  TakeUntil.swift
//  RxSwift
//
//  Created by Krunoslav Zaher on 6/7/15.
//  Copyright © 2015 Krunoslav Zaher. All rights reserved.
//

extension ObservableType {
    /**
     Returns the elements from the source observable sequence until the other observable sequence produces an element.

     - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)

     - parameter other: Observable sequence that terminates propagation of elements of the source sequence.
     - returns: An observable sequence containing the elements of the source sequence up to the point the other sequence interrupted further propagation.
     */
    public func takeUntil<O: ObservableType>(_ other: O)
        -> Observable<E> {
        return TakeUntil(source: asObservable(), other: other.asObservable())
    }

    /**
     Returns elements from an observable sequence until the specified condition is true.

     - seealso: [takeUntil operator on reactivex.io](http://reactivex.io/documentation/operators/takeuntil.html)

     - parameter behavior: Whether or not to include the last element matching the predicate.
     - parameter predicate: A function to test each element for a condition.
     - returns: An observable sequence that contains the elements from the input sequence that occur before the element at which the test passes.
     */
    public func takeUntil(_ behavior: TakeUntilBehavior,
                          predicate: @escaping (E) throws -> Bool)
        -> Observable<E> {
        return TakeUntilPredicate(source: asObservable(),
                                  behavior: behavior,
                                  predicate: predicate)
    }
}

/// Behaviors for the `takeUntil(_ behavior:predicate:)` operator.
public enum TakeUntilBehavior {
    /// Include the last element matching the predicate.
    case inclusive

    /// Exclude the last element matching the predicate.
    case exclusive
}

// MARK: - TakeUntil Observable

private final class TakeUntilSinkOther<Other, O: ObserverType>:
    ObserverType,
    LockOwnerType,
    SynchronizedOnType {
    typealias Parent = TakeUntilSink<Other, O>
    typealias E = Other

    fileprivate let _parent: Parent

    var _lock: RecursiveLock {
        return _parent._lock
    }

    fileprivate let _subscription = SingleAssignmentDisposable()

    init(parent: Parent) {
        _parent = parent
        #if TRACE_RESOURCES
            _ = Resources.incrementTotal()
        #endif
    }

    func on(_ event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next:
            _parent.forwardOn(.completed)
            _parent.dispose()
        case let .error(e):
            _parent.forwardOn(.error(e))
            _parent.dispose()
        case .completed:
            _subscription.dispose()
        }
    }

    #if TRACE_RESOURCES
        deinit {
            _ = Resources.decrementTotal()
        }
    #endif
}

private final class TakeUntilSink<Other, O: ObserverType>:
    Sink<O>,
    LockOwnerType,
    ObserverType,
    SynchronizedOnType {
    typealias E = O.E
    typealias Parent = TakeUntil<E, Other>

    fileprivate let _parent: Parent

    let _lock = RecursiveLock()

    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func on(_ event: Event<E>) {
        synchronizedOn(event)
    }

    func _synchronized_on(_ event: Event<E>) {
        switch event {
        case .next:
            forwardOn(event)
        case .error:
            forwardOn(event)
            dispose()
        case .completed:
            forwardOn(event)
            dispose()
        }
    }

    func run() -> Disposable {
        let otherObserver = TakeUntilSinkOther(parent: self)
        let otherSubscription = _parent._other.subscribe(otherObserver)
        otherObserver._subscription.setDisposable(otherSubscription)
        let sourceSubscription = _parent._source.subscribe(self)

        return Disposables.create(sourceSubscription, otherObserver._subscription)
    }
}

private final class TakeUntil<Element, Other>: Producer<Element> {
    fileprivate let _source: Observable<Element>
    fileprivate let _other: Observable<Other>

    init(source: Observable<Element>, other: Observable<Other>) {
        _source = source
        _other = other
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = TakeUntilSink(parent: self, observer: observer, cancel: cancel)
        let subscription = sink.run()
        return (sink: sink, subscription: subscription)
    }
}

// MARK: - TakeUntil Predicate

private final class TakeUntilPredicateSink<O: ObserverType>:
    Sink<O>, ObserverType {
    typealias Element = O.E
    typealias Parent = TakeUntilPredicate<Element>

    fileprivate let _parent: Parent
    fileprivate var _running = true

    init(parent: Parent, observer: O, cancel: Cancelable) {
        _parent = parent
        super.init(observer: observer, cancel: cancel)
    }

    func on(_ event: Event<Element>) {
        switch event {
        case let .next(value):
            if !_running {
                return
            }

            do {
                _running = try !_parent._predicate(value)
            } catch let e {
                self.forwardOn(.error(e))
                self.dispose()
                return
            }

            if _running {
                forwardOn(.next(value))
            } else {
                if _parent._behavior == .inclusive {
                    forwardOn(.next(value))
                }

                forwardOn(.completed)
                dispose()
            }
        case .error, .completed:
            forwardOn(event)
            dispose()
        }
    }
}

private final class TakeUntilPredicate<Element>: Producer<Element> {
    typealias Predicate = (Element) throws -> Bool

    fileprivate let _source: Observable<Element>
    fileprivate let _predicate: Predicate
    fileprivate let _behavior: TakeUntilBehavior

    init(source: Observable<Element>,
         behavior: TakeUntilBehavior,
         predicate: @escaping Predicate) {
        _source = source
        _behavior = behavior
        _predicate = predicate
    }

    override func run<O: ObserverType>(_ observer: O, cancel: Cancelable) -> (sink: Disposable, subscription: Disposable) where O.E == Element {
        let sink = TakeUntilPredicateSink(parent: self, observer: observer, cancel: cancel)
        let subscription = _source.subscribe(sink)
        return (sink: sink, subscription: subscription)
    }
}
