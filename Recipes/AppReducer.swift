import SwiftUI
import ComposableArchitecture

@Reducer
struct AppReducer {
  struct State: Equatable {
    var recipeListA = RecipeList.State(name: "A")
    var recipeListB = RecipeList.State(name: "B")
    var recipeListC = RecipeList.State(name: "C")
    
    @BindingState var destinationTag: DestinationTag? = .recipeListA
    
    enum DestinationTag: String, Equatable, CaseIterable {
      case recipeListA = "Recipes A"
      case recipeListB = "Recipes B"
      case recipeListC = "Recipes C"
    }
  }
  
  enum Action: BindableAction {
    case recipeListA(RecipeList.Action)
    case recipeListB(RecipeList.Action)
    case recipeListC(RecipeList.Action)
    case binding(BindingAction<State>)
  }
  
  var body: some ReducerOf<Self> {
    BindingReducer()
    Scope(state: \.recipeListA, action: \.recipeListA, child: RecipeList.init)
    Scope(state: \.recipeListB, action: \.recipeListB, child: RecipeList.init)
    Scope(state: \.recipeListC, action: \.recipeListC, child: RecipeList.init)
  }
}

struct AppView: View {
  let store: StoreOf<AppReducer>
  
  var body: some View {
    NavigationSplitView(
      //columnVisibility: .constant(.all),
      sidebar: {
        WithViewStore(store, observe: \.destinationTag) { viewStore in
          List(selection: viewStore.binding(get: { $0 }, send: { .binding(.set(\.$destinationTag, $0)) })) {
            ForEach(AppReducer.State.DestinationTag.allCases, id: \.self) { value in
              NavigationLink(value: value) {
                Text(value.rawValue.capitalized)
              }
            }
          }
          .navigationTitle("Recipes")
        }
      },
      content: {
        WithViewStore(store, observe: \.destinationTag) { viewStore in
          switch viewStore.state {
          case .recipeListA: RecipeListView(store: store.scope(state: \.recipeListA, action: { .recipeListA($0) }))
          case .recipeListB: RecipeListView(store: store.scope(state: \.recipeListB, action: { .recipeListB($0) }))
          case .recipeListC: RecipeListView(store: store.scope(state: \.recipeListC, action: { .recipeListC($0) }))
          case .none: EmptyView()
          }
        }
      },
      detail: {
        WithViewStore(store, observe: \.destinationTag) { viewStore in
          switch viewStore.state {
          case .recipeListA: RecipeListDetailsView(store: store.scope(state: \.recipeListA, action: { .recipeListA($0) }))
          case .recipeListB: RecipeListDetailsView(store: store.scope(state: \.recipeListB, action: { .recipeListB($0) }))
          case .recipeListC: RecipeListDetailsView(store: store.scope(state: \.recipeListC, action: { .recipeListC($0) }))
          case .none: EmptyView()
          }
        }
      }
    )
  }
}

// MARK: - RecipeList

@Reducer
struct RecipeList {
  struct State: Equatable {
    let name: String
    var recipes = IdentifiedArrayOf<API.Recipe>()
    @PresentationState var details: RecipeDetails.State?
    @PresentationState var destination: Destination.State?
  }
  
  enum Action {
    case task
    case setModels([API.Recipe])
    case showDetails(for: API.Recipe.ID?)
    case delete(model: API.Recipe.ID)
    case newRecipeButtonTapped
    case details(PresentationAction<RecipeDetails.Action>)
    case destination(PresentationAction<Destination.Action>)
  }
  
  @Dependency(\.api) var api
  
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        
      case .task:
        return .run { send in
          for await value in await self.api.models() {
            await send(.setModels(value))
          }
        }
        
      case let .setModels(value):
        state.recipes = .init(uniqueElements: value)
        return .none
        
      case let .delete(model: id):
        let isSelected = state.details?.id == id
        return .run { send in
          await self.api.delete(id)
          
          if isSelected {
            await send(.showDetails(for: nil))
          }
        }
        
      case let .showDetails(for: modelID):
        state.details = modelID
          .flatMap({ state.recipes[id: $0] })
          .flatMap({ RecipeDetails.State(parentName: state.name, model: $0) })
        return .none
        
      case .newRecipeButtonTapped:
        state.destination = .newRecipe()
        return .none
        
      case .details:
        return .none
        
      case .destination:
        return .none
      }
    }
    .ifLet(\.$details, action: \.details, destination: RecipeDetails.init)
    .ifLet(\.$destination, action: \.destination, destination: Destination.init)
  }
  
  @Reducer
  struct Destination {
    enum State: Equatable {
      case newRecipe(NewRecipe.State = .init())
    }
    enum Action {
      case newRecipe(NewRecipe.Action)
    }
    var body: some ReducerOf<Self> {
      Scope(state: \.newRecipe, action: \.newRecipe, child: NewRecipe.init)
    }
  }
}

struct RecipeListView: View {
  let store: StoreOf<RecipeList>
  
  var body: some View {
    WithViewStore(store, observe: { $0 }) { viewStore in
      List(selection: viewStore.binding(get: { $0.details?.id }, send: { .showDetails(for: $0) } )) {
        ForEach(viewStore.recipes) { model in
          NavigationLink(value: model.id) {
            Text(model.name)
          }
          .swipeActions {
            Button("Delete") {
              viewStore.send(.delete(model: model.id))
            }
            .tint(.red)
          }
        }
      }
      .navigationTitle("Content")
      .task { await viewStore.send(.task).finish() }
      .sheet(
        store: store.scope(state: \.$destination, action: { .destination($0) }),
        state: \.newRecipe,
        action: { .newRecipe($0) },
        content: NewRecipeSheet.init(store:)
      )
      .toolbar {
        Button(action: { viewStore.send(.newRecipeButtonTapped) }) {
          Image(systemName: "plus")
        }
      }
    }
  }
}

struct RecipeListDetailsView: View {
  let store: StoreOf<RecipeList>
  
  var body: some View {
    IfLetStore(
      store.scope(state: \.$details, action: { .details($0) }),
      then: RecipeDetailsView.init(store:)
    )
  }
}

// MARK: - RecipeDetails

@Reducer
struct RecipeDetails {
  struct State: Identifiable, Equatable {
    var id: API.Recipe.ID { model.id }
    let parentName: String
    let model: API.Recipe
  }
  enum Action {
    //...
  }
  var body: some ReducerOf<Self> {
    EmptyReducer()
  }
}

struct RecipeDetailsView: View {
  let store: StoreOf<RecipeDetails>
  
  var body: some View {
    WithViewStore(store, observe: { $0 }) { viewStore in
      VStack {
        Text("\(viewStore.model.name)")
          .font(.title)
        Text("Recipe - \(viewStore.parentName)")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("Detail")
    }
  }
}

// MARK: - NewRecipe

@Reducer
struct NewRecipe {
  struct State: Equatable {
    @BindingState var name = String()
    var model: API.Recipe? { .init(id: .init(), name: name) }
  }
  
  enum Action: BindableAction, Equatable {
    case cancelButtonTapped
    case saveButtonTapped
    case binding(BindingAction<State>)
  }
  
  @Dependency(\.api) var api
  @Dependency(\.dismiss) var dismiss
  
  var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
        
      case .cancelButtonTapped:
        return .run { _ in await self.dismiss() }
        
      case .saveButtonTapped:
        guard let model = state.model else { return .none }
        return .run { send in
          await api.save(model)
          await self.dismiss()
        }
        
      case .binding:
        return .none
        
      }
    }
  }
}

struct NewRecipeSheet: View {
  let store: StoreOf<NewRecipe>
  
  var body: some View {
    WithViewStore(store, observe: { $0 }) { viewStore in
      NavigationStack {
        List {
          TextField("Name", text: viewStore.$name)
        }
        .navigationTitle("New Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              viewStore.send(.cancelButtonTapped)
            }
          }
          ToolbarItem(placement: .primaryAction) {
            Button("Save") {
              viewStore.send(.saveButtonTapped)
            }
            .disabled(viewStore.name.isEmpty)
          }
        }
      }
    }
  }
}

// MARK: - SwiftUI Previews

#Preview {
  AppView(store: Store(
    initialState: AppReducer.State(),
    reducer: AppReducer.init
  ))
  .previewInterfaceOrientation(.landscapeLeft)
}
