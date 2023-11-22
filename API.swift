import Foundation
import ComposableArchitecture

struct API: DependencyKey {
  var models: @Sendable () async -> AsyncStream<[Recipe]>
  var save: @Sendable (Recipe) async -> Void
  var delete: @Sendable (Recipe.ID) async -> Void
  
  struct Recipe: Identifiable, Equatable {
    let id: UUID
    let name: String
  }
}

extension DependencyValues {
  var api: API {
    get { self[API.self] }
    set { self[API.self] = newValue }
  }
}

extension API {
  static var liveValue: Self {
    final actor ActorState {
      @Published var models = IdentifiedArrayOf<Recipe>(uniqueElements: [
        .init(id: .init(), name: "Model A"),
        .init(id: .init(), name: "Model B"),
        .init(id: .init(), name: "Model C"),
      ])
      func save(_ model: Recipe) {
        self.models.updateOrAppend(model)
      }
      func delete(_ modelID: Recipe.ID) {
        self.models.remove(id: modelID)
      }
    }
    let actor = ActorState()
    return Self(
      models: {
        AsyncStream { continuation in
          let task = Task {
            while !Task.isCancelled {
              for await value in await actor.$models.values {
                continuation.yield(value.elements)
              }
            }
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      },
      save: { await actor.save($0) },
      delete: { await actor.delete($0) }
    )
  }
}
