import SwiftUI
import PlaygroundSupport

class ViewModel {
    private var continuation: AsyncStream<Int>.Continuation?
    lazy private(set) var numbers = AsyncStream(Int.self) { continuation in
        self.continuation = continuation
    }
}

extension ViewModel {
    func next() {
        continuation?.yield(Int.random(in: 1...50))
    }
}

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

PlaygroundPage.current.setLiveView(ContentView())
