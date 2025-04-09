//
//  AuthContactCard.swift
//  Convos
//
//  Created by Joe on 4/9/25.
//

import SwiftUI
import Combine
import PhotosUI

// Main View
struct AuthOnboardingContactCardView: View {
    @StateObject private var viewModel = AuthOnboardingContactCardViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea() // Black background
            
            VStack(spacing: 0) {
                // Header with Cancel Button
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding(.leading, 16)
                    
                    Spacer()
                }
                .padding(.top, 16)
                
                // Main content
                VStack(spacing: 24) {
                    // Title and subtitle
                    VStack(spacing: 8) {
                        Text("Complete your\ncontact card")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Choose how you show up")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                    
                    // Contact Card
                    ContactCardView(
                        name: $viewModel.name,
                        avatarImage: viewModel.avatarImage,
                        isImagePickerPresented: $viewModel.isImagePickerPresented,
                        onImportTap: viewModel.handleImport
                    )
                    
                    // Footer text
                    Text("Add and edit Contact Cards anytime,\nor go Rando for extra privacy.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                
                Spacer()
                
                // Continue button
                VStack {
                    Button(action: viewModel.handleContinue) {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1)
                                )
                            
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.name.isEmpty)
                    
                    Text("Continue")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.top, 8)
                }
                .padding(.bottom, 24)
            }
            .sheet(isPresented: $viewModel.isImagePickerPresented) {
                ImagePicker(image: $viewModel.avatarImage)
            }
        }
        .navigationBarHidden(true)
    }
}

// Contact Card View
struct ContactCardView: View {
    @Binding var name: String
    var avatarImage: UIImage?
    @Binding var isImagePickerPresented: Bool
    var onImportTap: () -> Void
    
    var body: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                VStack(spacing: 16) {
                    // Avatar and Import button
                    HStack(alignment: .top) {
                        // Avatar
                        ZStack(alignment: .bottomLeading) {
                            Button(action: { isImagePickerPresented = true }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 90, height: 90)
                                    
                                    if let image = avatarImage {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 90, height: 90)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "photo")
                                            .font(.system(size: 30))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                            }
                            
                            // Camera button
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black, lineWidth: 1)
                                    )
                                
                                Image(systemName: "camera")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Spacer()
                        
                        // Import button
                        Button("Import") {
                            onImportTap()
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                    }
                    
                    // Name input field
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        
                        TextField("Enter your name", text: $name)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding(.bottom, 12)
                }
                .padding(16)
            }
            .frame(height: 200)
        }
    }
}

// ImagePicker using PhotosUI
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()
            
            guard let itemProvider = results.first?.itemProvider, itemProvider.canLoadObject(ofClass: UIImage.self) else { return }
            
            itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                DispatchQueue.main.async {
                    guard let self = self, let image = image as? UIImage else { return }
                    self.parent.image = image
                }
            }
        }
    }
}

// ViewModel
class AuthOnboardingContactCardViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var avatarImage: UIImage?
    @Published var isLoading: Bool = false
    @Published var isImagePickerPresented: Bool = false
    
    // Services would be injected in a real app
    private let userService = UserService()
    private let storageService = StorageService()
    
    func handleContinue() {
        guard !name.isEmpty else { return }
        
        isLoading = true
        
        // First upload the image if available
        let imageUploadTask: AnyPublisher<URL?, Never> = avatarImage != nil ?
            storageService.uploadProfileImage(image: avatarImage!)
                .map { Optional.some($0) }
                .catch { _ in Just(nil) }
                .eraseToAnyPublisher()
            : Just(nil).eraseToAnyPublisher()
        
        // Then create the user
        imageUploadTask
            .flatMap { [weak self] imageUrl -> AnyPublisher<Bool, Error> in
                guard let self = self else { return Fail(error: NSError(domain: "Unknown", code: 0)).eraseToAnyPublisher() }
                
                return self.userService.createUser(
                    name: self.name,
                    username: self.generateRandomUsername(from: self.name),
                    avatarUrl: imageUrl?.absoluteString
                )
            }
            .receive(on: RunLoop.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    
                    if case .failure(let error) = completion {
                        print("Error creating user: \(error)")
                        // Handle error in real app - show alert, etc.
                    }
                },
                receiveValue: { [weak self] success in
                    self?.isLoading = false
                    if success {
                        // Navigate to next screen in real app
                        print("User created successfully")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    func handleImport() {
        // In a real app, this would navigate to the import view
        print("Import tapped")
    }
    
    private func generateRandomUsername(from name: String) -> String {
        let sanitizedName = name.lowercased().replacingOccurrences(of: " ", with: "")
        let randomSuffix = String(Int.random(in: 1000...9999))
        return "\(sanitizedName)\(randomSuffix)"
    }
    
    private var cancellables = Set<AnyCancellable>()
}

// Service implementations
class UserService {
    func createUser(name: String, username: String, avatarUrl: String?) -> AnyPublisher<Bool, Error> {
        // In a real app, this would make an API call to create the user
        return Future<Bool, Error> { promise in
            // Simulate network delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Simulate success
                promise(.success(true))
            }
        }
        .eraseToAnyPublisher()
    }
}

class StorageService {
    func uploadProfileImage(image: UIImage) -> AnyPublisher<URL, Error> {
        // In a real app, this would upload the image to a storage service
        return Future<URL, Error> { promise in
            // Simulate network delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                // Simulate success with a fake URL
                let fakeURL = URL(string: "https://example.com/profile-images/\(UUID().uuidString).jpg")!
                promise(.success(fakeURL))
            }
        }
        .eraseToAnyPublisher()
    }
}

// Preview
struct AuthOnboardingContactCardView_Previews: PreviewProvider {
    static var previews: some View {
        AuthOnboardingContactCardView()
            .preferredColorScheme(.dark)
    }
}
