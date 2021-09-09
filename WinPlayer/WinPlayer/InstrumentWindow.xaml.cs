using NAudio.Wave;
using System;
using System.Collections.Generic;
using System.Diagnostics;
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
using System.Windows.Shapes;

namespace WinPlayer
{
    /// <summary>
    /// Interaction logic for InstrumentWindow.xaml
    /// </summary>
    public partial class InstrumentWindow : Window
    {
        public InstrumentWindow()
        {
            InitializeComponent();
        }

        public Models.Instrument? Instrument { get; set; }      
        private IInputSource? InputSource { get; set; }
        private InstrumentPlayer? _player = null;

        private void Button_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }

        public void ShowDialog(Models.Instrument instrument)
        {
            Instrument = instrument;
            InstrumentDisplay.SetInstrument(instrument);

            InputSource = Globals.InputSource ?? throw new Exception("No input source set");
            InputSource.PlayNote += InputSource_PlayNote;

            if (Globals.WaveOut != null)
            {
                Globals.WaveOut.Stop();
                Globals.WaveOut.Dispose();
                Globals.WaveOut = null;
            }

            if (_player != null)
                _player = null;

            ShowDialog();

            InstrumentDisplay.WritePart();
        }

        private void InputSource_PlayNote(object? sender, InputEvent e)
        {
            if (Globals.WaveOut != null)
            {
                Globals.WaveOut.Stop();
                Globals.WaveOut.Dispose();
                Globals.WaveOut = null;
            }

            if (_player != null)
                _player = null;

            InstrumentDisplay.WritePart();

            if (Instrument == null)
                return;

            var note = new Models.Note() { NoteNum = e.NoteNumber, InstrumentNumber = Instrument.InstrumentNumber };

            _player = new InstrumentPlayer(Instrument, note);
            Globals.WaveOut = new WaveOut();
            Globals.WaveOut.Init(_player);
            Globals.WaveOut.Play();
        }

        private void Window_Closed(object? sender, EventArgs e)
        {
            if (InputSource != null)
                InputSource.PlayNote -= InputSource_PlayNote;

            if (Globals.WaveOut != null)
            {
                Globals.WaveOut.Stop();
                Globals.WaveOut.Dispose();
                Globals.WaveOut = null;
            }
        }
    }
}
