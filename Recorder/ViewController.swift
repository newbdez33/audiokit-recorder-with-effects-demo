import UIKit
import AudioKitUI
import AudioKit

class ViewController: UIViewController {

    var micMixer: AKMixer!
    var recorder: AKNodeRecorder!
    var player: AKPlayer!
    var tape: AKAudioFile!
    var micBooster: AKBooster!
    var moogLadder: AKMoogLadder!
    var mainMixer: AKMixer!
    var cheerPlayer: AKPlayer!      //欢呼声
    var effect:AKOperationEffect!   //变音
    var reverb:AKReverb!            //混音
    var backgroundSoundPlayer: AKPlayer!    //背景音乐
    
    var recordingDummyMixer: AKMixer!
    
    let mic = AKMicrophone()
    var state = State.readyToRecord
    
    @IBOutlet private var plot: AKNodeOutputPlot?
    @IBOutlet private weak var infoLabel: UILabel!
    @IBOutlet private weak var resetButton: UIButton!
    @IBOutlet private weak var mainButton: UIButton!
    @IBOutlet private weak var loopButton: UIButton!
    @IBOutlet private weak var reverbButton: UIButton!
    @IBOutlet private weak var cheerButton: UIButton!
    @IBOutlet private weak var pitchSlider: AKSlider!
    
    enum State {
        case readyToRecord
        case recording
        case readyToPlay
        case playing
        
    }
    
    //初始化背景音乐播放器
    func buildBackgroundSoundPlayer() {
        do
        {
            let file = try AKAudioFile(readFileName: "Country.m4a")
            backgroundSoundPlayer = AKPlayer(audioFile: file)
            backgroundSoundPlayer.isLooping = true
            backgroundSoundPlayer.volume = 0.5;
            backgroundSoundPlayer.stop()
        } catch {
            print("creat backgroundSoundPlayer faild")
        }
    }
    
    //创建欢呼声播放器
    func buildCheerPlayer() {
        do
        {
            let file = try AKAudioFile(readFileName: "claps.mp3")
            cheerPlayer = AKPlayer(audioFile: file)
            cheerPlayer.isLooping = false
            cheerPlayer.volume = 1
            cheerPlayer.stop()
        } catch {
            print("get file failed")
        }
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        
        print(getDocumentsDirectory())
        mic.volume = 1
        // Clean tempFiles !
        AKAudioFile.cleanTempDirectory()
        // Session settings 设置缓冲区大小
        AKSettings.bufferLength = .medium
        do {
            //设置组件是可录可播放
            try AKSettings.setSession(category: .playAndRecord, with: .allowBluetoothA2DP)
        } catch {
            AKLog("Could not set session category.")
        }
        
        //是否在启用音频输入时输出到扬声器(而不是接收器)
        AKSettings.defaultToSpeaker = false
        AKSettings.audioInputEnabled = true
        
        //self.buildBackgroundSoundPlayer()
        self.buildCheerPlayer()
        //self.buildEffectPlayer()
        
        //对mic 做混音
        let delay = AKDelay(mic)
        delay.time = 0.1 // seconds
        delay.feedback = 0 // Normalized Value 0 - 1        //回音次数
        delay.dryWetMix = 0 // Normalized Value 0 - 1      //将声音变得很慵懒，拉长语调
        reverb = AKReverb(delay)
        reverb.loadFactoryPreset(.cathedral)
        reverb.stop()
        
        effect = AKOperationEffect(reverb) { player, parameters in
            let sinusoid = AKOperation.sineWave(frequency: parameters[2])
            let shift = parameters[0] + sinusoid * parameters[1] / 2.0
            return player.pitchShift(semitones: shift)
        }
        effect.parameters = [0, 0, 0]
        effect.stop()

        // Patching
        micMixer = AKMixer(effect, cheerPlayer)
        micBooster = AKBooster(micMixer)
        
        // Will set the level of microphone monitoring
        micBooster.gain = 0
        //创建录音控制器
        recorder = try? AKNodeRecorder(node: micMixer)
        if let file = recorder.audioFile {
            //设置播放器
            player = AKPlayer(audioFile: file)
        }
        //是否循环播放
        player.isLooping = false
        //播放完成后的回调
        player.completionHandler = playingEnded
        
        
        moogLadder = AKMoogLadder(player)
        moogLadder.stop()
        
        // Create a muted mixer for recording audio, so AudioKit will pull audio through the recording Mixer, but not play it through the output.
        recordingDummyMixer = AKMixer(micBooster)
        recordingDummyMixer.volume = 0
        
        mainMixer = AKMixer(moogLadder, recordingDummyMixer, cheerPlayer)
        
        AudioKit.output = mainMixer
        do {
            try AudioKit.start()
        } catch {
            AKLog("AudioKit did not start!")
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        plot?.node = mic
        setupButtonNames()
        setupUIForRecording()
        pitchSlider.range = -1_2 ... 1_2
        pitchSlider.callback = updateTimePitch
        //backgroundSoundPlayer.play()
    }

    // CallBack triggered when playing has ended
    // Must be seipatched on the main queue as completionHandler
    // will be triggered by a background thread
    func playingEnded() {
        DispatchQueue.main.async {
            self.setupUIForPlaying ()
        }
    }
    
    @IBAction func mainButtonTouched(sender: UIButton) {
        switch state {
        case .readyToRecord :
            infoLabel.text = "Recording"
            mainButton.setTitle("Stop", for: .normal)
            state = .recording
            // microphone will be monitored while recording
            // only if headphones are plugged
            if AKSettings.headPhonesPlugged {
                micBooster.gain = 1
            }
            do {
                try recorder.record()
            } catch { AKLog("Errored recording.") }
            
        case .recording :
            // Microphone monitoring is muted
            micBooster.gain = 1
            tape = recorder.audioFile!
            player.load(audioFile: tape)
            
            if let _ = player.audioFile?.duration {
                recorder.stop()
                tape.exportAsynchronously(name: "TempTestFile.m4a",
                                          baseDir: .documents,
                                          exportFormat: .m4a) {_, exportError in
                                            if let error = exportError {
                                                AKLog("Export Failed \(error)")
                                            } else {
                                                AKLog("Export succeeded")
                                            }
                }
                setupUIForPlaying()
            }
        case .readyToPlay :
            player.play()
            player.volume = 1;
            infoLabel.text = "Playing..."
            mainButton.setTitle("Stop", for: .normal)
            state = .playing
            plot?.node = player
            
        case .playing :
            player.stop()
            setupUIForPlaying()
            plot?.node = mic
        }
    }
    
    struct Constants {
        static let empty = ""
    }
    
    func setupButtonNames() {
        resetButton.setTitle(Constants.empty, for: UIControl.State.disabled)
        mainButton.setTitle(Constants.empty, for: UIControl.State.disabled)
        loopButton.setTitle(Constants.empty, for: UIControl.State.disabled)
        reverbButton.setTitle(Constants.empty, for: UIControl.State.disabled)
        cheerButton.setTitle(Constants.empty, for: UIControl.State.disabled)
    }
    
    func setupUIForRecording () {
        state = .readyToRecord
        infoLabel.text = "Ready to record"
        mainButton.setTitle("Record", for: .normal)
        resetButton.isEnabled = false
        resetButton.isHidden = true
        micBooster.gain = 0
    }
    
    func setupUIForPlaying () {
        let recordedDuration = player != nil ? player.audioFile?.duration  : 0
        infoLabel.text = "Recorded: \(String(format: "%0.1f", recordedDuration!)) seconds"
        mainButton.setTitle("Play", for: .normal)
        state = .readyToPlay
        resetButton.isHidden = false
        resetButton.isEnabled = true
    }
    
    @IBAction func loopButtonTouched(sender: UIButton) {
        
        if player.isLooping {
            player.isLooping = false
            sender.setTitle("Loop is Off", for: .normal)
        } else {
            player.isLooping = true
            sender.setTitle("Loop is On", for: .normal)
            
        }
        
    }
    @IBAction func resetButtonTouched(sender: UIButton) {
        player.stop()
        plot?.node = mic
        do {
            try recorder.reset()
        } catch { AKLog("Errored resetting.") }
        
        //try? player.replaceFile((recorder.audioFile)!)
        setupUIForRecording()
    }
    
    @IBAction func playCheerVoiceTouched(sender: UIButton) {
        if cheerPlayer.isPlaying {
            cheerPlayer.stop()
        }else {
            cheerPlayer.play()
        }
    }
    
    func updateTimePitch(value: Double) {
        print(value)
        effect.parameters[0] = value
    }
    
    @IBAction func playReverbTouched(sender: UIButton) {
        if reverb.isStarted {
            reverb.stop()
            reverbButton.setTitle("Reverb is Off", for: UIControl.State.normal)
        } else {
            reverb.start()
            reverbButton.setTitle("Reverb is On", for: UIControl.State.normal)
        }
    }
}

