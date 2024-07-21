# Departing Combine

Combine is being phased out, prompting us to consider minimising its use. In this document, I explain how we create a simple SwiftUI view using Combine for managing state. Then, I show how to remove Combine and use async sequences instead.

The SwiftUI view we will build should display a number inside a circle on the screen. This number should change whenever a user presses a button.

## Building with Combine

A SwiftUI View needs some form of data to present information. We can achieve this by using an `ObservableObject`.

For an `ObservableObject` to notify a SwiftUI view of updates, it requires at least one property marked with `@Published`. This mechanism is part of the Combine framework.

```mermaid
flowchart TD
    ObservableObject --> |@Published| View
```


The following code stubs out the UI of the app: 

```swift
struct ContentView: View {
    
    var body: some View {
        VStack(spacing: 200) {
            image(for: 15)
                .font(.largeTitle)
            Button("Next") {
                // action
            }
        }
        .frame(width: 200, height: 400)
    }
}

extension ContentView {
    private func image(for int: Int) -> Image {
        Image(systemName: int.description + ".circle")
    }
}
```
- Create a SwiftUI `ContentView` that displays a number inside a circle
- Initially, the number inside the circle is hardcoded to 15


Now that the UI is stubbed out, we want to allow for the number to change. For that we need a data source for our `ContentView`. This is where the `ObservableObject` comes into play.

```swift
import Combine

class ViewModel: ObservableObject {
    @Published var counter = 0
    
    func next() {
        counter = Int.random(in: 0...50)
    }
}
```
- Include a published property called `counter`. This is used to communicate when the value changes so our `ContentView` can react
- A function called `next()` is added, which will be the action used in the button
- `next()` modifies the counter property by assigning it a random integer value between 0 and 50

We can now connect our ViewModel to the view as follows:

```swift
struct ContentView: View {
    @StateObject private var viewModel = ViewModel()

    var body: some View {
        VStack(spacing: 200) {
            image(for: viewModel.counter)
                .font(.largeTitle)
            Button("Next") {
                viewModel.next()
            }
        }
        .frame(width: 200, height: 400)
    }
}

extension ContentView {
    func image(for int: Int) -> Image {
        Image(systemName: int.description + ".circle")
    }
}
```
- Create an instance of `ViewModel` as a `StateObject` to receive update notifications `@StateObject` ensures the ViewModel instance persists across view updates
-  Call `ViewModel`'s `next()` function for the button action
- Button triggers the viewModel's `next()` function when tapped

Since the `ViewModel` is a `StateObject`, it ensures that whenever there's a change detected within it, the view automatically refreshes to reflect the updated state of `counter`.

## Removing Combine - part one

In this initial step towards removing Combine entirely, we refocus its usage to encapsulate communication solely within the `ViewModel`.

### Break the ContentView - ViewModel Connection

Modify the the code:

```swift
class ViewModel {
    @Published private var counter = 0
    
    // Rest of ViewModel implementation
}
```
```swift
struct ContentView: View {
    private var viewModel = ViewModel()

    // Rest of ContentView implementation
}
```

- The `counter` property is made private, ensuring it's inaccessible to `ContentView`. The code will not compile now
- Remove `ViewModel`s' conformance to `ObservableObject`. This means `ViewModel` can no longer be a `StateObject`. It also means the mechanism by which `ContentView` gets its updates has been broken

### Set Up New Data Source for ContentView

Next, create a new property called `numbers`:

```swift
class ViewModel {
    @Published private var counter = 0
    lazy private(set) var numbers = counter
    
    // Rest of ViewModel implementation
}
```
- Initially `numbers` it will be set to `counter`
- The numbers property is initialised lazily using `lazy`. This ensures that it's initialised only when accessed for the first time, which is suitable since it depends on `counter` which doesn't exist at this point. Initialisers run before `self` is fully initialised
- Make counter a `var`. lazy properties must be a `var`
- Mark `numbers` setter as private, restricting external modification. This follows the [principle of least privilege](https://www.geeksforgeeks.org/least-privilege-in-information-security), ensuring that only the ViewModel itself can modify numbers.

> [!CAUTION]
> Omitting `lazy` results in a complier error:
‼️ "Cannot use instance member 'counter' within property initializer; property initializers run before 'self' is available"

> [!NOTE]  
> At this point `numbers` is of type Int.
We can confirm this by adding `let _ = print(type(of: counter))` inside the `next()` function and then tapping the button to output the type.

Modify `numbers`:

```swift
class ViewModel {
    @Published private var counter = 0
    lazy private(set) var numbers = $counter.values
    
    // Rest of ViewModel implementation
}
```

- Change `counter` to `$counter`. This gives us a `Publisher<Int, Never>`. A publisher of Ints that never fails
- Then using the `.values` operator make `numbers` an async sequence of Ints that never fails (`AsyncSequence<Int, Never>`)

By using `$counter.values`, we transition from a Combine Publisher to an AsyncSequence. This change decouples the View from direct Combine dependencies.

### Connect New Data Source to ContentView

As it stands there is no mechanism to update `ContentView` when our view model's `counter` changes. To fix this we add the following:

```swift
struct ContentView: View {
    private var viewModel = ViewModel()
    @State private var currentValue = 0

    var body: some View {
        VStack(spacing: 200) {
            image(for: currentValue)
                .font(.largeTitle)
            Button("Next") {
                viewModel.next()
            }
        }
        .frame(width: 200, height: 400)
    }
}
```
- Add a new property `@State private var currentValue = 0`
- Pass the `currentValue` to our function that returns the image view

At this point things will compile but view will not get updates back from `ViewModel`. `ContentView` needs to get the next element of the AsyncSequence `numbers` when it's available.

A standard for loop won't work because `numbers` isn't a sequence.
`numbers` is a async sequence.

Create a new function `ContentView` to set our `currentValue` to the last element of `numbers`:

```swift
struct ContentView: View {
    
    // Rest of ContentView 

    private func listenForNumbers() async {
        for await number in viewModel.numbers {
            currentValue = number
        }
    }
}
```
- Use `await` keyword because it might be awhile before we get our next number in the sequence
- If we use `await` there is a possible suspension point so either the for loop needs to be wrapped inside of a task or `listenForNumbers()` should be marked as `async`
- Inside the for loop assign `currentValue` to the next number in the async sequence

Now call the `listenForNumbers()` function with the `.task` modifier and with `await`:
```swift
.task {
    await listenForTask()
}
````

Now our code looks like the following:

```swift
struct ContentView: View {
    private var viewModel = ViewModel()
    @State private var currentValue = 0

    var body: some View {
        VStack(spacing: 200) {
            image(for: currentValue)
                .font(.largeTitle)
            Button("Next") {
                viewModel.next()
            }
        }
        .frame(width: 200, height: 400)
        .task {
            await listenForNumbers()
        }
    }
}

extension ContentView {
    private func image(for int: Int) -> Image {
        Image(systemName: int.description + ".circle")
    }
}

extension ContentView {
    private func listenForNumbers() async {
        for await number in viewModel.numbers {
            currentValue = number
        }
    }
}

class ViewModel {
    @Published private var counter = 0
    lazy private(set) var numbers = $counter.values
    
    func next() {
        counter = Int.random(in: 0...50)
    }
}
```
## Removing Combine - part two


It's time to begin eliminating Combine and `@Published` from our `ViewModel`. Instead, communication between the `ViewModel` and `ContentView` will be handled via NotificationCenter.

Previously, our ViewModel utilised Combine and `@Published` to create an integer publisher, which we used inside of an async sequence to feed the `ContentView`.

Next, we'll modify the functionality of the 'Next' button. Rather than directly assigning the `counter` from a random variable, we will now post a notification:

```swift
import Combine
import Foundation

class ViewModel {
    @Published private var counter = 0
    lazy private(set) var numbers = $counter.values
    let notificationName = Notification.Name("CounterNotificaiton")
    let counterKey = "counterKey"
    
    func next() {
        NotificationCenter.default
            .post(name: notificationName,
                  object: self,
                  userInfo: [counterKey: Int.random(in: 1...50)]
            )
    }
}

````

- Import `Foundation`
- Define `notificationName` constant for convenience
- In the `next()` method, a notification with the specified `notificationName` is post
- The current instance of `ViewModel` acts as the source posting the notification
- Define `counterKey` constant for accessing the user info dictionary key
- Post the random Int as the entry in the dictionary with the key `counterKey`

> [!NOTE]  
> Note that this code does not involve async operations. Posting a notification happens synchronously at a specific time.

Since we're not observing notifications to update the counter and consequently the `numbers` property, running the app won't reflect changes despite posting a new random number

In a new extension for ViewModel register for notifications:

```swift
extension ViewModel {
    private func registerForNotifications() {
        NotificationCenter.default
            .addObserver(forName: notificationName,
                         object: self,
                         queue: nil) { notification in
            if let userInfo = notification.userInfo,
               let counter = userInfo[self.counterKey] as? Int {
              self.counter = counter
            }
          }
    }
}
````
- Add new function `registerForNotifications()`
- `registerForNotifications()` uses `NotificationCenter.default` and adds an observer
- When a notification matching `notificationName` is received, a closure is executed. 
- Within this closure:
   - Check if the notification contains a `userInfo` dictionary
   -  If the dictionary exists, attempt to retrieve the value associated with the `counterKey`
    - If successful, cast this value to an integer and assign it to `counter`

Before running the app make sure to call `registerForNotifications()`:

```swift
class ViewModel {
    @Published private var counter = 0
    lazy private(set) var numbers = $counter.values
    let notificationName = Notification.Name("CounterNotificaiton")
    let counterKey = "counterKey"

    init() {
        registerForNotifications()
    }
    
    // The rest of ViewModel implementation
}
```
- Add an initialiser for `ViewModel`
- Call `registerForNotifications()` inside the initialiser

If you run the app now things will work as before. 

### Async Sequence Notifications

Make the following changes to the `ViewModel`. It will break and in turn also break `ContentView` because the data source `numbers` will be removed:

```swift
let notificationName = Notification.Name("CounterNotificaiton")
let counterKey = "counterKey"

class ViewModel {

}

extension ViewModel {
    private func registerForNotifications() {
        NotificationCenter.default
            .addObserver(forName: notificationName,
                         object: self,
                         queue: nil) { notification in
            if let userInfo = notification.userInfo,
               let counter = userInfo[counterKey] as? Int {
            }
          }
    }
}
```
- Remove the `@Published` property `counter` from `ViewModel`
- Within the closure of `registerForNotifications()`'s observer, delete the assignment `self.counter = counter`
- Delete the `numbers` property entirely from `ViewModel`
- Delete the `import Combine` statement as it is no longer needed by `ViewModel` 
- Delete the initialiser in `ViewModel` and the invocation of `registerForNotifications()`
- Move `let notificationName = Notification.Name("CounterNotificaiton")` and `let counterKey = "counterKey"` outside of the `ViewModel` class
- Adjust the usage of `counterKey` by removing `self.` within `registerForNotifications()` since the constants are no longer members of `ViewModel`

Now that we've decimated our `ViewModel`, we'll reconstruct it using asynchronous sequences of notifications from NotificationCenter. This approach leverages notifications for asynchronous operations.

Add a new property to `ViewModel`:

```swift
class ViewModel {
    let numbers = NotificationCenter.default
        .notifications(named: notificationName)
}
```
- Introduce a new `numbers` property within `ViewModel`, defined as `NotificationCenter.default.notifications(named: notificationName)`
- This property utilises a new method of NotificationCenter, returning an `AsyncSequence<Notification, Never>`

### Async Sequence of Notifications to Async Sequence of Ints 

Currently our `numbers` property is of type `AsyncSequence<Notification, Never>`, while our `ContentView` requires `AsyncSequence<Int, Never>`. 

To align `numbers` with this requirement, let's analyse the closure of `addObserver` in `registerForNotifications()` and see how we can modify `numbers` to achieve the same logic.

  - The first statement in the closure is `if let userInfo = notification.userInfo`
- This statement stops if `notification.userInfo` is `nil`; if not `nil`, it unwraps and assigns it to `userInfo`
- We can achieve this behaviour with sequences like `numbers` using the `compactMap` operator
- Using `.compactMap` with key path `userInfo`,  we are doing the same as the `if let`. Taking every notification and if it's not `nil`, extracting the `userInfo` dictionary.

```swift
class ViewModel {
    let numbers = NotificationCenter.default
        .notifications(named: notificationName)
        .compactMap(\.userInfo)
}
```
- Add `compactMap(\.userInfo)` operator to `numbers`

Now `numbers` is of type `AsyncSequence<[:], Never>`

Let's look at the second statement in the closure of `addObserver` in `registerForNotifications()` and then modify `numbers` to have the same behaviour:

- The second statement in the closure checks `if let counter = userInfo[counterKey] as? Int`
- This line ensures there is a value in the `userInfo` dictionary for the key `counterKey` and verifies if its type is `Int`
- Similarly, we can adapt numbers to utilise `compactMap` to achieve equivalent behaviour

```swift
class ViewModel {
    let numbers = NotificationCenter.default
        .notifications(named: notificationName)
        .compactMap(\.userInfo)
        .compactMap { userInfo in userInfo[counterKey] as? Int }
}
```
- Add the `.compactMap { userInfo in userInfo[counterKey] as? Int }` operator to numbers to extract and map the integer value associated with `counterKey` from each notification's `userInfo`

Now that numbers is of type `AsyncSequence<Int, Never>`, it precisely matches what `ContentView` expects. Consequently, `registerForNotifications()` can be deleted.

Now run the app. Everything should function as it did before, even though ViewModel no longer uses Combine or `@Published`.

### Summary

When the `Next` button is tapped, a notification is posted containing a `userInfo` dictionary with a random integer.

On the receiving end:
- We start with `AsyncSequence<Notification, Never>`
- Transform it to `AsyncSequence<[AnyHashable: Any], Never>`
- Further transform it to an `AsyncSequence<Int, Never>`, which matches the type expected by `ContentView`


Given that `ContentView` remains unchanged, here is the new version of the `ViewModel`:

```swift
let notificationName = Notification.Name("CounterNotificaiton")
let counterKey = "counterKey"

class ViewModel {
    let numbers = NotificationCenter.default
        .notifications(named: notificationName)
        .compactMap(\.userInfo)
        .compactMap { userInfo in userInfo[counterKey] as? Int }
}

extension ViewModel {
     func next() {
        NotificationCenter.default
            .post(name: notificationName,
                  object: self,
                  userInfo: [counterKey: Int.random(in: 1...50)]
            )
    }
}
```