import SwiftUI
import Speech
import AVFoundation
import Combine // 💥 FIXED: Added the missing import shown in Screenshot 2026-06-05 at 7.05.46 PM.png

// MARK: - DATABASE MODELS
enum SessionType: String, Codable, CaseIterable {
    case normal = "Normal Roll 🥋"
    case competition = "Competition Day 🥇"
    case lazy = "Lazy Day 🦥"
    case rest = "Rest Day 😴"
    case injured = "Injured 🤕"
}

struct TrainingLog: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var sessionType: SessionType
    var rawTranscript: String
    var positionsTried: [String]
    var competitorName: String
    var summary: String
}

class JournalManager: ObservableObject {
    @Published var logs: [TrainingLog] = [] {
        didSet { saveToDisk() }
    }
    @Published var positionsComfort: [String: Int] = [
        "Closed Guard": 3, "Half Guard (Smashed)": 3, "Side Control Survival": 3,
        "Mount (Suffocating)": 3, "Back Control": 3, "De la Riva": 3, "Leg Entanglements": 3
    ] {
        didSet { UserDefaults.standard.set(positionsComfort, forKey: "bjj_positions") }
    }
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "bjj_logs"),
           let decoded = try? JSONDecoder().decode([TrainingLog].self, from: data) {
            self.logs = decoded
        }
        if let savedPositions = UserDefaults.standard.dictionary(forKey: "bjj_positions") as? [String: Int] {
            self.positionsComfort = savedPositions
        }
    }
    
    func addLog(type: SessionType, transcript: String, competitor: String, positions: [String]) {
        let cleanTranscript = transcript.isEmpty ? "No vocal breakdown provided." : transcript
        let newLog = TrainingLog(
            date: Date(),
            sessionType: type,
            rawTranscript: cleanTranscript,
            positionsTried: positions,
            competitorName: competitor,
            summary: "Logged as \(type.rawValue)"
        )
        logs.insert(newLog, at: 0)
    }
    
    private func saveToDisk() {
        if let encoded = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(encoded, forKey: "bjj_logs")
        }
    }
    
    var dateToSessionType: [String: SessionType] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var dict: [String: SessionType] = [:]
        for log in logs.reversed() {
            let key = formatter.string(from: log.date)
            dict[key] = log.sessionType
        }
        return dict
    }
}

// MARK: - MAIN INTERFACE
struct ContentView: View {
    @StateObject var manager = JournalManager()
    
    // App Tracking States
    @State private var selectedType: SessionType = .normal
    @State private var isRecording = false
    @State private var transcriptText = ""
    @State private var competitorInput = ""
    @State private var selectedPositions: Set<String> = []
    @State private var isProcessingAI = false
    
    // Popup Alerts
    @State private var showLoveAlert = false
    @State private var activeLoveMessage = ""
    
    let standardLoveMessages = [
        "I love you! Now go take a shower, you smell like laundry and defeat. ❤️",
        "You are doing grape! 🍇 Best grappler on the planet!",
        "Oss! Super proud of you, honey! (Even if you got tapped out) 🥰",
        "I love you more than you love buying expensive new Gi colors. 🥋",
        "Great job today! Your neck is safe at home. 💛",
        "You're doing amazing! I promise I won't choke you in your sleep. 😘"
    ]
    
    let compHypeMessages = [
        "This is the day! Go grab that gold medal and bring it home to me! 🥇🔥",
        "Go break some grips and take some names! I'll be cheering the loudest! 📣❤️",
        "Time to unleash the beast! No mercy, go rip off those double legs! 🦁",
        "Win or learn, you're still coming home to a wife who thinks you're an absolute weapon. Now go crush them! ⚔️"
    ]
    
    let restOrInjuredMessages = [
        "Rest up, honey! The mats aren't running away. Proud of you for smart recovery. 🛌",
        "Ice packs and couch time activated. Sending you extra healing hugs! 🩹❤️",
        "Good job listening to your joints instead of your ego today. Love you! 🧠"
    ]
    
    let lazyDayMessages = [
        "For real?! Skip day? Somewhere out there, your brackets rival is doing extra burpees. 🦥👀",
        "Skipping mat time to lounge? Bold strategy for a competitor! I still love you though. 😘",
        "I love you, but let's be honest... your couch guard proficiency is currently a 5/5. 🛋️",
        "A lazy day?! Who are you and what have you done with my hardcore competitor husband? 🤔"
    ]
    
    // Audio Engines
    @State private var audioEngine = AVAudioEngine()
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?

    var body: some View {
        TabView {
            // TAB 1: LOG SESSIONS
            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What kind of day was it?")
                                .font(.subheadline).bold().foregroundColor(.secondary)
                            Picker("Session Type", selection: $selectedType) {
                                ForEach(SessionType.allCases, id: \.self) { type in
                                    Text(type.rawValue.replacingOccurrences(of: " Day", with: "")).tag(type)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        
                        if selectedType == .normal || selectedType == .competition || selectedType == .injured {
                            VStack {
                                Text(isRecording ? "Listening to your excuses..." : "Tap to Log Training Voice Notes")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Button(action: {
                                    if isRecording { stopRecording() } else { startRecording() }
                                }) {
                                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                        .resizable()
                                        .frame(width: 90, height: 90)
                                        .foregroundColor(isRecording ? .red : .purple)
                                        .shadow(radius: 5)
                                }
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                            
                            VStack(alignment: .leading) {
                                Text("Your Mat Rant:")
                                    .font(.caption).bold().foregroundColor(.secondary)
                                Text(transcriptText.isEmpty ? "Talk here. Tag positions or summarize what went down..." : transcriptText)
                                    .font(.body)
                                    .italic(transcriptText.isEmpty)
                                    .padding()
                                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(selectedType == .competition ? "Who was your opponent bracket match?" : "Who Smoked You Today? (Nemesis Name)")
                                    .font(.subheadline).bold()
                                TextField(selectedType == .competition ? "e.g. Bracket Final Match" : "e.g. That 18-year-old wrestler...", text: $competitorInput)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Positions Tested / Attempted:")
                                    .font(.subheadline).bold()
                                    .padding(.bottom, 2)
                                
                                FlowLayout(items: Array(manager.positionsComfort.keys)) { pos in
                                    Button(action: {
                                        if selectedPositions.contains(pos) { selectedPositions.remove(pos) }
                                        else { selectedPositions.insert(pos) }
                                    }) {
                                        Text(pos)
                                            .font(.caption).bold()
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(selectedPositions.contains(pos) ? Color.purple : Color(.secondarySystemBackground))
                                            .foregroundColor(selectedPositions.contains(pos) ? .white : .primary)
                                            .cornerRadius(20)
                                    }
                                }
                            }
                        } else if selectedType == .lazy {
                            VStack(spacing: 12) {
                                Text("🦥 For Real?! Lazy Day Mode")
                                    .font(.title3).bold()
                                    .foregroundColor(.orange)
                                Text("Skipping training because your bed or the couch gave you a structural submission hold? Shame! For real, get back out there tomorrow!")
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                        } else {
                            VStack(spacing: 12) {
                                Text("🧘‍♂️ Complete Rest Mode Activated")
                                    .font(.title3).bold()
                                    .foregroundColor(.green)
                                Text("No mats, no sweat, no chokes. Go play video games or eat a burger. Your joints will thank you.")
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        Button(action: processAndSaveSession) {
                            HStack {
                                if isProcessingAI {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .padding(.trailing, 8)
                                    Text("AI is cleaning your Gi...")
                                } else {
                                    Text(selectedType == .rest ? "Log Rest Day" : (selectedType == .lazy ? "Admit Lazy Day 🦥" : "Lock It in the Vault"))
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(selectedType == .competition ? Color.orange : (selectedType == .lazy ? Color.orange : Color.red))
                            .cornerRadius(10)
                        }
                        .disabled(isProcessingAI)
                        .padding(.top, 10)
                    }
                    .padding()
                }
                .navigationTitle("Post-Mat Ledger")
                .background(Color(.systemGroupedBackground))
                .alert(isPresented: $showLoveAlert) {
                    Alert(
                        title: Text(selectedType == .competition ? "CHAMPIONSHIP FUEL 🏆" : (selectedType == .lazy ? "EXCUSE ALERT 🦥" : "Message From Your #1 Fan 📣")),
                        message: Text(activeLoveMessage),
                        dismissButton: .default(Text("Oss! 🥋"))
                    )
                }
            }
            .tabItem { Label("Log Day", systemImage: "mic.fill") }
            
            // TAB 2: MAT ATTENDANCE CALENDAR
            NavigationView {
                VStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Attendance Report Card:")
                            .font(.caption).bold().foregroundColor(.secondary)
                        Text(attendanceCommentary(logs: manager.logs))
                            .font(.headline)
                            .foregroundColor(.purple)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    ScrollView {
                        VStack(alignment: .leading) {
                            Text("Your Last 28 Days Calendar Grid:")
                                .font(.subheadline).bold()
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                                ForEach((0..<28).reversed(), id: \.self) { dayOffset in
                                    let targetDate = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
                                    let dateString = formatDateToString(targetDate)
                                    let sessionType = manager.dateToSessionType[dateString]
                                    
                                    VStack {
                                        Text(formatDayLabel(targetDate))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        
                                        ZStack {
                                            Circle()
                                                .frame(width: 38, height: 38)
                                                .foregroundColor(circleColor(for: sessionType))
                                            
                                            Text(circleEmoji(for: sessionType))
                                                .font(.caption)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .background(sessionType != nil ? circleColor(for: sessionType).opacity(0.15) : Color.clear)
                                    .cornerRadius(8)
                                }
                            }
                            .padding()
                        }
                    }
                    Spacer()
                }
                .navigationTitle("Mat Tracker")
            }
            .tabItem { Label("Mat Clock", systemImage: "calendar") }
            
            // TAB 3: EGO MATRIX
            NavigationView {
                List {
                    Section(header: Text("Ego Check: How comfortable are we actually?")) {
                        ForEach(Array(manager.positionsComfort.keys.sorted()), id: \.self) { position in
                            VStack(alignment: .leading) {
                                Text(position)
                                    .font(.body).bold()
                                HStack {
                                    Text(comfortLabel(for: manager.positionsComfort[position, default: 3]))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    ForEach(1...5, id: \.self) { num in
                                        Image(systemName: num <= manager.positionsComfort[position, default: 3] ? "skull.fill" : "skull")
                                            .foregroundColor(.red)
                                            .onTapGesture {
                                                manager.positionsComfort[position] = num
                                            }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .navigationTitle("Ego Matrix")
            }
            .tabItem { Label("Ego Check", systemImage: "brain.head.profile") }
            
            // TAB 4: LOG HISTORY
            NavigationView {
                List(manager.logs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(log.date, style: .date)
                                .font(.caption).bold().foregroundColor(.purple)
                            Spacer()
                            Text(log.sessionType.rawValue)
                                .font(.caption2).bold()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        if !log.rawTranscript.isEmpty && log.sessionType != .rest && log.sessionType != .lazy {
                            Text("\"" + log.rawTranscript + "\"")
                                .font(.body)
                                .italic()
                                .foregroundColor(.primary)
                        }
                        
                        HStack {
                            if !log.competitorName.isEmpty {
                                Text(log.sessionType == .competition ? "Opponent: \(log.competitorName)" : "Target: \(log.competitorName)")
                                    .font(.caption).bold()
                                    .foregroundColor(.red)
                            }
                            Spacer()
                            if !log.positionsTried.isEmpty {
                                Text("Positions: " + log.positionsTried.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .navigationTitle("The Evidence")
            }
            .tabItem { Label("History", systemImage: "archivebox.fill") }
        }
    }
    
    // MARK: - FUNNY CODE HELPERS
    func comfortLabel(for rating: Int) -> String {
        switch rating {
        case 1: return "Absolute panic mode"
        case 2: return "Accepting my fate"
        case 3: return "Surviving, barely"
        case 4: return "Hey, I'm doing the smashing now"
        case 5: return "Basically Gordon Ryan"
        default: return "Unknown tier"
        }
    }
    
    func attendanceCommentary(logs: [TrainingLog]) -> String {
        let normalCount = logs.filter { $0.sessionType == .normal }.count
        let compCount = logs.filter { $0.sessionType == .competition }.count
        let totalMatDays = normalCount + compCount
        
        switch totalMatDays {
        case 0: return "Total couch potato status. Do you even own a belt?"
        case 1...2: return "A casual mat visitor. Your belt is probably collecting dust."
        case 3...5: return "Solid warrior! You are officially harder to kill."
        default: return "Absolute mat rat. Your laundry bill must be insane!"
        }
    }
    
    func circleColor(for type: SessionType?) -> Color {
        guard let type = type else { return Color(.tertiarySystemGroupedBackground) }
        switch type {
        case .normal: return .purple
        case .competition: return .orange
        case .lazy: return .orange
        case .rest: return .green
        case .injured: return .red
        }
    }
    
    func circleEmoji(for type: SessionType?) -> String {
        guard let type = type else { return "💨" }
        switch type {
        case .normal: return "🥋"
        case .competition: return "🥇"
        case .lazy: return "🦥"
        case .rest: return "😴"
        case .injured: return "🩹"
        }
    }
    
    func formatDateToString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    func formatDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
    
    // MARK: - UPGRADED CLOUD AI PIPELINE
    func processAndSaveSession() {
        if selectedType == .rest || selectedType == .lazy || transcriptText.isEmpty {
            executeSave(finalTranscript: transcriptText)
            return
        }
        
        isProcessingAI = true
        
        let apiKey = let apiKey = "YOUR_OPENAI_API_KEY"
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            executeSave(finalTranscript: transcriptText)
            return
        }
        
        let systemPrompt = """
        You are an elite Brazilian Jiu-Jitsu expert assistant. Your sole job is to clean up messy phonetically fumbled audio transcripts recorded by a tired competitor right after sparring. Fix any BJJ term fumbles:
        - "deliver reeva" or "de la riva" -> "De la Riva"
        - "key mora" or "kimura" -> "Kimura"
        - "omo plata" -> "Omoplata"
        - "bury bolo" -> "Berimbolo"
        - "guard step" -> "Guard Pass"
        Clean the grammar but keep his exact original context and mood intact. Return ONLY the polished final paragraph.
        """
        
        let jsonBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcriptText]
            ],
            "temperature": 0.3
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonBody)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { // 💥 FIXED: Cleaned up double '.main.main' typo loop here
                self.isProcessingAI = false
                
                if let data = data, error == nil,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let cleanText = message["content"] as? String {
                    
                    self.executeSave(finalTranscript: cleanText.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    self.executeSave(finalTranscript: self.transcriptText)
                }
            }
        }.resume()
    }
    
    private func executeSave(finalTranscript: String) {
        manager.addLog(type: selectedType, transcript: finalTranscript, competitor: competitorInput, positions: Array(selectedPositions))
        
        switch selectedType {
        case .competition:
            activeLoveMessage = compHypeMessages.randomElement() ?? ""
        case .lazy:
            activeLoveMessage = lazyDayMessages.randomElement() ?? ""
        case .rest, .injured:
            activeLoveMessage = restOrInjuredMessages.randomElement() ?? ""
        case .normal:
            activeLoveMessage = standardLoveMessages.randomElement() ?? ""
        }
        
        showLoveAlert = true
        
        transcriptText = ""
        competitorInput = ""
        selectedPositions.removeAll()
        selectedType = .normal
    }
    
    // MARK: - NATIVE MIC AUDIO CONTROL
    func startRecording() {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                self.transcriptText = result.bestTranscription.formattedString
            }
            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        isRecording = true
    }
    
    func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
    }
}

// MARK: - STYLING FLOW WRAPPER
struct FlowLayout: View {
    var items: [String]
    var viewForItem: (String) -> AnyView
    init<V: View>(items: [String], @ViewBuilder viewForItem: @escaping (String) -> V) {
        self.items = items
        self.viewForItem = { AnyView(viewForItem($0)) }
    }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                var width = CGFloat.zero
                var height = CGFloat.zero
                ForEach(items, id: \.self) { item in
                    viewForItem(item)
                        .padding([.horizontal, .vertical], 4)
                        .alignmentGuide(.leading) { d in
                            if (abs(width - d.width) > geo.size.width) {
                                width = 0
                                height -= d.height
                            }
                            let result = width
                            if item == items.last { width = 0 } else { width -= d.width }
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            if item == items.last { height = 0 } else { height = 0 }
                            return result
                        }
                }
            }
        }
        .frame(minHeight: 140)
    }
}
