using NAudio.Midi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;
using WinPlayer.Player;
using WinPlayer.Waveform;

namespace WinPlayer
{
    /// <summary>
    /// Interaction logic for MainWindow.xaml
    /// </summary>
    public partial class MainWindow : Window
    {
        private readonly MidiIn _midiIn;

        private Models.Song _song;
        private SongPlayer? _songPlayer = null;

        private int _patternNumber;
        private Controls.TrackEditor? _trackEditor = null;

        private readonly System.Timers.Timer _timer;

        private Models.Pattern _currentPattern;

        public MainWindow()
        {
            InitializeComponent();

            LoadSettings();

            LoadSong(Globals.Settings.AutoSaveFileName);

            _midiIn = new MidiIn(0);
            _midiIn.ErrorReceived += _midiIn_ErrorReceived;
            _midiIn.Start();

            Globals.InputSource = new MidiSource(_midiIn);

            for (var device = 0; device < MidiIn.NumberOfDevices; device++)
            {
                Debug.WriteLine(MidiIn.DeviceInfo(device).ProductName);
            }

            DisplaySong();

            NoteEdit.Initialise();
            NoteEdit.Editing = true;
            NoteEdit.SetSong(_song ?? throw new Exception("song is null"));
            NoteEdit.UpdateInstruments();

            Track0.NoteChanged += Track_NoteChanged;
            Track1.NoteChanged += Track_NoteChanged;
            Track2.NoteChanged += Track_NoteChanged;
            Track3.NoteChanged += Track_NoteChanged;

            Track4.NoteChanged += Track_NoteChanged;
            Track5.NoteChanged += Track_NoteChanged;
            Track6.NoteChanged += Track_NoteChanged;
            Track7.NoteChanged += Track_NoteChanged;

            Track8.NoteChanged += Track_NoteChanged;
            Track9.NoteChanged += Track_NoteChanged;
            TrackA.NoteChanged += Track_NoteChanged;
            TrackB.NoteChanged += Track_NoteChanged;

            TrackC.NoteChanged += Track_NoteChanged;
            TrackD.NoteChanged += Track_NoteChanged;
            TrackE.NoteChanged += Track_NoteChanged;
            TrackF.NoteChanged += Track_NoteChanged;

            Track0.GotFocus += Track_GotFocus;
            Track1.GotFocus += Track_GotFocus;
            Track2.GotFocus += Track_GotFocus;
            Track3.GotFocus += Track_GotFocus;

            Track4.GotFocus += Track_GotFocus;
            Track5.GotFocus += Track_GotFocus;
            Track6.GotFocus += Track_GotFocus;
            Track7.GotFocus += Track_GotFocus;

            Track8.GotFocus += Track_GotFocus;
            Track9.GotFocus += Track_GotFocus;
            TrackA.GotFocus += Track_GotFocus;
            TrackB.GotFocus += Track_GotFocus;

            TrackC.GotFocus += Track_GotFocus;
            TrackD.GotFocus += Track_GotFocus;
            TrackE.GotFocus += Track_GotFocus;
            TrackF.GotFocus += Track_GotFocus;

            _currentPattern = _song.Patterns[0];

            Instruments.InstrumentChange += Instruments_InstrumentChange;
            Instruments.InstrumentListChange += Instruments_InstrumentListChange;
            Instruments.BeforeNewClick += (_, _) => { NoteEdit.Editing = false; };
            Instruments.AfterNewClick += (_, _) => { NoteEdit.Editing = true; };

            Patterns.PatternChange += Patterns_PatternChange;
            Patterns.PatternListChange += Patterns_PatternListChange;
            Patterns.PatternLengthChange += Patterns_PatternLengthChange;

            NoteEdit.NoteChanged += NoteEdit_NoteChanged;

            TrackControl.TrackChanged += TrackEditor_TrackChanged;

            _timer = new System.Timers.Timer();
            _timer.Interval = 20000;
            _timer.Elapsed += _timer_Elapsed;
            _timer.Enabled = true;
        }

        private void TrackEditor_TrackChanged(object? sender, Controls.TrackControlTradeUpdateEventArgs e)
        {
            _trackEditor?.Refresh();
        }

        private void Patterns_PatternLengthChange(object? sender, Controls.PatternLengthChangeEventArgs e)
        {
            DisplayPattern();
        }

        private void Patterns_PatternListChange(object? sender, Controls.PatternListChangeEventArgs e)
        {
            
        }

        private void Patterns_PatternChange(object? sender, Controls.PatternChangeEventArgs e)
        {
            _patternNumber = e.Pattern.Number;
            DisplayPattern();
        }

        private void LoadSettings()
        {
            if (!File.Exists(Globals.SettingsFileName))
                return;

            var file = File.ReadAllText(Globals.SettingsFileName);

            var settings = JsonConvert.DeserializeObject<Settings>(file);

            if (settings != null)
                Globals.Settings = settings;

            AutoSaveText.Text = Globals.Settings.AutoSaveFileName;
            FileNameText.Text = Globals.Settings.SongFileName;
            ExportNameText.Text = Globals.Settings.ExportFileName;
            X16RunNameText.Text = Globals.Settings.X16RunFileName;
        }

        private void SaveSettings()
        {
            var toSave = JsonConvert.SerializeObject(Globals.Settings);

            File.WriteAllText(Globals.SettingsFileName, toSave);
        }

        private void _timer_Elapsed(object sender, System.Timers.ElapsedEventArgs e)
        {
            SaveSong(Globals.Settings.AutoSaveFileName);
        }

        public void LoadSong(string filename)
        {
            Models.Song? song = null;

            if (File.Exists(filename))
            {
                var json = File.ReadAllText(filename);

                song = JsonConvert.DeserializeObject<Models.Song>(json);
            }

            if (song == null)
            {
                song = new Models.Song();
                song.Patterns.Add(new Models.Pattern());
            }

            if (song.Patterns[0].Tracks.Count < 16)
            {
                while (song.Patterns[0].Tracks.Count < 16)
                {
                    song.Patterns[0].Tracks.Add(new Models.Track());
                }
            }

            _song = song;
            _patternNumber = 0;
        }

        public void SaveSong(string filename)
        {
            foreach(var pattern in _song.Patterns)
            {
                foreach(var trade in pattern.Tracks)
                {
                    var c = 0;
                    foreach(var note in trade.Notes)
                    {
                        if (note.Position == 0)
                            note.Position = c;
                        c++;
                    }
                }
            }

            try
            {
                if (_song == null)
                    return;

                var json = JsonConvert.SerializeObject(_song);

                File.WriteAllText(filename, json);
            } 
            catch
            {

            }
        }

        private void Track_GotFocus(object sender, RoutedEventArgs e)
        {
            var track = e.Source as Controls.TrackEditor;

            if (track == null)
                return;

            _trackEditor = track;
            TrackControl.SetTrack(track.Value);
        }

        private void NoteEdit_NoteChanged(object? sender, Controls.NoteEditorChangedEventArgs e)
        {
            if (_trackEditor == null)
                return;

            Dispatcher.Invoke(() =>
            {
                _trackEditor.NoteChange(e.Note);
            });
        }

        private void Instruments_InstrumentListChange(object? sender, Controls.InstrumentListChangeEventArgs e)
        {
            NoteEdit.UpdateInstruments();
        }

        private void Instruments_InstrumentChange(object? sender, Controls.InstrumentChangeEventArgs e)
        {
            NoteEdit.SetInstrument(e.Instrument.InstrumentNumber);
            TrackControl.SetInstrument(e.Instrument.InstrumentNumber);
        }

        private void Track_NoteChanged(object? sender, Controls.TrackEditorNoteChangedEventArgs e)
        {
            NoteEdit.SetNote(e.Note);
        }

        private void DisplaySong()
        {
            Instruments.Value = _song.Instruments;
            Patterns.Value = _song.Patterns;
            Playlist.Text = string.Join(", ", _song.Playlist);
            DisplayPattern();
        }

        private void DisplayPattern()
        {
            _currentPattern = _song.Patterns[_patternNumber];
            Track0.Value = _currentPattern.Tracks[0];
            Track1.Value = _currentPattern.Tracks[1];
            Track2.Value = _currentPattern.Tracks[2];
            Track3.Value = _currentPattern.Tracks[3];

            Track4.Value = _currentPattern.Tracks[4];
            Track5.Value = _currentPattern.Tracks[5];
            Track6.Value = _currentPattern.Tracks[6];
            Track7.Value = _currentPattern.Tracks[7];
        
            Track8.Value = _currentPattern.Tracks[8];
            Track9.Value = _currentPattern.Tracks[9];
            TrackA.Value = _currentPattern.Tracks[10];
            TrackB.Value = _currentPattern.Tracks[11];

            TrackC.Value = _currentPattern.Tracks[12];
            TrackD.Value = _currentPattern.Tracks[13];
            TrackE.Value = _currentPattern.Tracks[14];
            TrackF.Value = _currentPattern.Tracks[15];
        }

        private void _midiIn_ErrorReceived(object? sender, MidiInMessageEventArgs e)
        {
            Debug.WriteLine($"Time {e.Timestamp} Message 0x{e.RawMessage:X8} Event {e.MidiEvent}");
        }

        private void TabControl_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (JsonTab.IsSelected)
            {
                var json = JsonConvert.SerializeObject(_song);

                JsonOutput.Text = json;
            }
        }

        private void Window_Closing(object sender, System.ComponentModel.CancelEventArgs e)
        {
            SaveSong(Globals.Settings.AutoSaveFileName);
            SaveSettings();
        }
        private void PlayButton_Click(object sender, RoutedEventArgs e) => Play(true);
        private void PlayPatternButton_Click(object sender, RoutedEventArgs e) => Play(false);

        private void Play(bool playSong)
        {

            if (_songPlayer != null)
            {
                Globals.WaveOut?.Stop();
                NoteEdit.Editing = true;
                _songPlayer = null;
                Globals.WaveOut = null;
                PlayButton.Content = "Play Song";
                PlayPatternButton.Content = "Play Pattern";
                return;
            }
            else
            {
                Globals.WaveOut?.Stop();
                Globals.WaveOut = null;
            }

            NoteEdit.Editing = false;

            Globals.WaveOut = new WaveOut();

            _songPlayer = new SongPlayer(_song, playSong ? null : _currentPattern.Number);
            Globals.WaveOut.Init(_songPlayer);
            Globals.WaveOut.Play();

            PlayButton.Content = "Stop";
            PlayPatternButton.Content = "Stop";
        }

        private void AutoSavetext_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (string.IsNullOrEmpty(AutoSaveText.Text))
            {
                AutoSaveText.Text = Globals.Settings.AutoSaveFileName;
                return;
            }
            Globals.Settings.AutoSaveFileName = AutoSaveText.Text;
        }

        private void FilenameText_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (string.IsNullOrEmpty(FileNameText.Text))
            {
                FileNameText.Text = Globals.Settings.SongFileName;
                return;
            }
            Globals.Settings.SongFileName = FileNameText.Text;
        }

        private void ExportNameText_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (string.IsNullOrEmpty(ExportNameText.Text))
            {
                ExportNameText.Text = Globals.Settings.ExportFileName;
                return;
            }
            Globals.Settings.ExportFileName = ExportNameText.Text;
        }

        private void ExportButton_Click(object sender, RoutedEventArgs e)
        {
            Globals.Exporter.Export(_song, Globals.Settings.ExportFileName);
        }

        private void SaveButton_Click(object sender, RoutedEventArgs e)
        {
            SaveSong(Globals.Settings.SongFileName);
        }

        private void LoadButton_Click(object sender, RoutedEventArgs e)
        {
            LoadSong(Globals.Settings.SongFileName);
            DisplaySong();
        }

        private void Playlist_TextChanged(object sender, TextChangedEventArgs e)
        {
            var parts = Playlist.Text.Split(',');

            if (_song == null)
                return;

            _song.Playlist = new List<int>();

            foreach(var p in parts)
            {
                if (int.TryParse(p, out var pattern))
                {
                    _song.Playlist.Add(pattern);
                }
            }
        }

        private void X16Button_Click(object sender, RoutedEventArgs e)
        {
            if (!string.IsNullOrEmpty(Globals.Settings.X16RunFileName))
            {
                Globals.Exporter.Export(_song, Globals.Settings.ExportFileName);

                var path = System.IO.Path.GetDirectoryName(Globals.Settings.X16RunFileName);

                var process = new Process();

                process.StartInfo.FileName = "powershell";
                process.StartInfo.Arguments = $"-ExecutionPolicy Unrestricted {Globals.Settings.X16RunFileName}";

                process.StartInfo.WorkingDirectory = path ?? "";
                process.Start();
            }
        }

        private void X16RunNameText_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (string.IsNullOrEmpty(X16RunNameText.Text))
            {
                X16RunNameText.Text = Globals.Settings.X16RunFileName;
                return;
            }
            Globals.Settings.X16RunFileName = X16RunNameText.Text;
        }
    }
}

