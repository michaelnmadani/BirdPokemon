import SwiftUI
import PhotosUI

struct CaptureFlowView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var locationService = LocationService()

    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = capturedImage {
                    ClassificationView(
                        image: image,
                        region: appState.selectedRegion,
                        locationService: locationService
                    ) {
                        capturedImage = nil
                    }
                } else {
                    landing
                }
            }
            .navigationTitle("Capture")
            .onAppear { locationService.requestWhenInUse() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                capturedImage = image
                showCamera = false
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, newValue in
            Task {
                guard let newValue,
                      let data = try? await newValue.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                capturedImage = image
                pickerItem = nil
            }
        }
    }

    private var landing: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "camera.viewfinder")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(Color.accentColor)

            Text("Spot a bird?")
                .font(.title.bold())
            Text("Take a photo and we'll try to ID it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                #if !targetEnvironment(simulator)
                Button {
                    showCamera = true
                } label: {
                    Label("Open camera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                #endif

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Pick from library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}
