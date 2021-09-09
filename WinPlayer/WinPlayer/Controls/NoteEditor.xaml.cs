using NAudio.Wave;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
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
using System.Windows.Threading;
using WinPlayer.Command;

namespace WinPlayer.Controls
{
    public class NoteEditorChangedEventArgs : EventArgs
    {
        public Models.Note Note { get; }

        public NoteEditorChangedEventArgs(Models.Note note)
        {
            Note = note.Clone();
        }
    }

    public partial class NoteEditor : UserControl
    {
        public event EventHandler<NoteEditorChangedEventArgs>? NoteChanged;

        private IInputSource? _inputSource;

        private Models.Song? _song;
        private Models.Note? _value = null;

        private bool _fireEvents = true;
        private InstrumentPlayer? _player = null;

        public bool Editing { get; set; } = false;

        public NoteEditor()
        {
            InitializeComponent();
            CommandList.ItemsSource = Enum.GetValues(typeof(Commands)).Cast<Commands>();
        }

        public void Initialise()
        {
            _inputSource = Globals.InputSource ?? throw new Exception("null inputsource");
            _inputSource.PlayNote += _inputSource_PlayNote;
        }

        public void SetSong(Models.Song song)
        {
            _song = song;
        }

        public void UpdateInstruments()
        {
            InstrumentList.ItemsSource = null;
            InstrumentList.ItemsSource = _song?.Instruments;
        }

        public void SetInstrument(int instrumentNumber)
        {
            _value ??= new Models.Note();

            _value.NoteNum = instrumentNumber;
            InstrumentList.SelectedIndex = instrumentNumber;
        }

        public void SetNote(Models.Note note)
        {
            _value = note?.Clone();
            _fireEvents = false;
            Dispatcher.BeginInvoke(UpdateDisplay);
            _fireEvents = true;
        }

        private void _inputSource_PlayNote(object? sender, InputEvent e)
        {
            if (!Editing || _value == null)
                return;

            _value.NoteNum = e.NoteNumber;
            UpdateNote(true);

            Dispatcher.BeginInvoke(UpdateDisplay);

            Globals.WaveOut?.Stop();
            _player = null;

            var instrument = _song?.Instruments.FirstOrDefault(i => i.InstrumentNumber == _value.InstrumentNumber) ?? throw new Exception();
            _player = new InstrumentPlayer(instrument, _value);

            Globals.WaveOut = new WaveOut();
            Globals.WaveOut.Init(_player);
            Globals.WaveOut.Play();
        }

        private void UpdateNote(bool newNoteNum = false)
        {
            if (_value == null)
                _value = new Models.Note();

            Dispatcher.BeginInvoke(() =>
            {
                if (NoteChanged != null && _fireEvents && (!FreeplayCheck.IsChecked ?? false))
                    NoteChanged.Invoke(this, new NoteEditorChangedEventArgs(_value));
            });
        }

        private void UpdateDisplay()
        {
            NoteText.Text = _value?.NoteStr ?? "";

            if (_value?.NoteNum != 0)
            {
                InstrumentList.SelectedValue = _value?.InstrumentNumber;
                CommandParameter.Text = _value?.CommandParam.ToString();
                CommandList.SelectedItem = _value?.Command;
            }
        }

        private void InstrumentList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_fireEvents && _value != null)
            {
                _value.InstrumentNumber = InstrumentList.SelectedIndex;
            }
        }

        private void CommandList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_fireEvents && _value != null)
            {
                _value.Command = (Commands)CommandList.SelectedItem;
            }
        }

        private void CommandParameter_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (_fireEvents && _value != null)
            {
                if (short.TryParse(CommandParameter.Text, out var commandParam))
                {
                    _value.CommandParam = commandParam;
                }
            }
        }

        private void Button_Click(object sender, RoutedEventArgs e)
        {
            if (NoteChanged != null && _value != null)
                NoteChanged.Invoke(this, new NoteEditorChangedEventArgs(_value));
        }
    }
}
