import SwiftUI

/// Stand-in for `@State`. The SDK in the Command Line Tools ships `@State` as a macro whose plugin only comes with
/// Xcode, so this builds the same thing from `@StateObject`. It behaves like `@State` in views.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    private final class Box: ObservableObject {
        @Published var value: Value
        init(_ v: Value) { value = v }
    }
    @StateObject private var box: Box

    init(wrappedValue: Value) { _box = StateObject(wrappedValue: Box(wrappedValue)) }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}
