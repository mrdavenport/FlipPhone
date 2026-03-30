import SwiftUI
import AudioToolbox

#if DEBUG
struct SystemSoundTestView: View {
    @Environment(\.dismiss) private var dismiss
    
    struct SystemSound {
        let id: SystemSoundID
        let name: String
        let description: String
    }
    
    let systemSounds: [SystemSound] = [
        // Common system sounds
        SystemSound(id: 1000, name: "New Mail", description: "Mail received notification"),
        SystemSound(id: 1001, name: "Mail Sent", description: "Mail sent confirmation"),
        SystemSound(id: 1003, name: "SMS Received", description: "Text message received"),
        SystemSound(id: 1004, name: "SMS Sent", description: "Text message sent"),
        SystemSound(id: 1005, name: "Voicemail", description: "Voicemail notification"),
        SystemSound(id: 1006, name: "Photo Shutter", description: "Camera shutter sound"),
        SystemSound(id: 1007, name: "Tweet Sent", description: "Tweet sent confirmation"),
        
        // UI Sounds
        SystemSound(id: 1050, name: "Tink", description: "UI sound - Tink"),
        SystemSound(id: 1051, name: "Tink", description: "UI sound - Tink 2"),
        SystemSound(id: 1052, name: "Tink", description: "UI sound - Tink 3"),
        SystemSound(id: 1053, name: "Tink", description: "UI sound - Tink 4"),
        SystemSound(id: 1054, name: "Tink Success", description: "Success sound (Pay Success)"),
        SystemSound(id: 1055, name: "Tink", description: "UI sound - Tink 5"),
        SystemSound(id: 1056, name: "Tink", description: "UI sound - Tink 6"),
        SystemSound(id: 1057, name: "Tink Positive", description: "Positive action sound"),
        
        // Alert sounds
        SystemSound(id: 1008, name: "Anticipate", description: "Alert sound"),
        SystemSound(id: 1009, name: "Bloom", description: "Alert sound"),
        SystemSound(id: 1010, name: "Calypso", description: "Alert sound"),
        SystemSound(id: 1011, name: "Choo Choo", description: "Alert sound"),
        SystemSound(id: 1012, name: "Descent", description: "Alert sound"),
        SystemSound(id: 1013, name: "Fanfare", description: "Celebratory sound"),
        SystemSound(id: 1014, name: "Ladder", description: "Alert sound"),
        SystemSound(id: 1015, name: "Minuet", description: "Alert sound"),
        SystemSound(id: 1016, name: "News Flash", description: "Alert sound"),
        SystemSound(id: 1017, name: "Noir", description: "Alert sound"),
        SystemSound(id: 1018, name: "Sherwood Forest", description: "Alert sound"),
        SystemSound(id: 1019, name: "Spell", description: "Alert sound"),
        SystemSound(id: 1020, name: "Suspense", description: "Alert sound"),
        SystemSound(id: 1021, name: "Telegraph", description: "Alert sound"),
        SystemSound(id: 1022, name: "Tiptoes", description: "Alert sound"),
        SystemSound(id: 1023, name: "Typewriters", description: "Alert sound"),
        SystemSound(id: 1024, name: "Update", description: "Alert sound"),
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(systemSounds, id: \.id) { sound in
                            Button(action: {
                                AudioServicesPlaySystemSound(sound.id)
                            }) {
                                HStack(spacing: 16) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sound.name)
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                        
                                        Text(sound.description)
                                            .font(.system(size: 13, weight: .regular, design: .rounded))
                                            .foregroundColor(.white.opacity(0.6))
                                        
                                        Text("ID: \(sound.id)")
                                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 24, weight: .regular, design: .rounded))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if sound.id != systemSounds.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                                    .padding(.leading, 20)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(20)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("System Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}
#endif

