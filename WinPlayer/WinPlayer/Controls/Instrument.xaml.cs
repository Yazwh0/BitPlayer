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

namespace WinPlayer.Controls
{
    /// <summary>
    /// Interaction logic for InstrumentPart.xaml
    /// </summary>
    public partial class Instrument : UserControl
    {
        private class VolumeBinding
        {
            public int Volume { get; set; }
        }

        public Models.Instrument Value { get; private set; } = new Models.Instrument();

        public Instrument()
        {
            InitializeComponent();
        }

        public void SetInstrument(Models.Instrument instrument)
        {
            Value = instrument;

            Start.Value = instrument.StartEnvelope?.Deconstruct() ?? (0, 16, 63);
            Attack.Value = instrument.AttackEnvelope?.Deconstruct() ?? (2, 50, 63);
            Decay.Value = instrument.DecayEnvelope?.Deconstruct() ?? (5, 40, 63);
            Sustain.Value = instrument.SustainEnvelope?.Deconstruct() ?? (20, 30, 63);
            Release.Value = instrument.ReleaseEnvelope?.Deconstruct() ?? (5, 0, 63);

            WaveType.SelectedIndex = (int)instrument.WaveType;

            InstrumentName.Text = instrument.Name;

            if (instrument.Levels == null || !instrument.Levels.Any() )
                ApplyEnvelopes();

            UpdateLevels();
            Repeat.Text = instrument.RepeatStart.ToString();
        }

        public void WritePart()
        {
            Value.StartEnvelope = new Models.Envelope();
            Value.StartEnvelope.TimeLength = Start.Value.Time;
            Value.StartEnvelope.Volume = Start.Value.Volume;
            Value.StartEnvelope.Width = Start.Value.Width;

            Value.AttackEnvelope = new Models.Envelope();
            Value.AttackEnvelope.TimeLength = Attack.Value.Time;
            Value.AttackEnvelope.Volume = Attack.Value.Volume;
            Value.AttackEnvelope.Width = Attack.Value.Width;

            Value.DecayEnvelope = new Models.Envelope();
            Value.DecayEnvelope.TimeLength = Decay.Value.Time;
            Value.DecayEnvelope.Volume = Decay.Value.Volume;
            Value.DecayEnvelope.Width = Decay.Value.Width;

            Value.SustainEnvelope = new Models.Envelope();
            Value.SustainEnvelope.TimeLength = Sustain.Value.Time;
            Value.SustainEnvelope.Volume = Sustain.Value.Volume;
            Value.SustainEnvelope.Width = Sustain.Value.Width;

            Value.ReleaseEnvelope = new Models.Envelope();
            Value.ReleaseEnvelope.TimeLength = Release.Value.Time;
            Value.ReleaseEnvelope.Volume = Release.Value.Volume;
            Value.ReleaseEnvelope.Width = Release.Value.Width;
        }

        private void UpdateLevels()
        {
            if (Value.Levels.All(i => i.Position == 0))
            {
                for(var i = 0; i < Value.Levels.Count; i++)
                {
                    Value.Levels[i].Position = i;
                }
            }
            DataGrid.ItemsSource = Value.Levels;
        }

        private void ButtonApply_Click(object sender, RoutedEventArgs e)
        {
            ApplyEnvelopes();
        }

        private void ApplyEnvelopes()
        {
            var levels = new List<Models.InstrumentStep>();

            AddEnvelope(levels, Attack.Value.Time, Start.Value.Volume, Attack.Value.Volume, Start.Value.Width, Attack.Value.Width, Decay.Value.Time == 0);
            AddEnvelope(levels, Decay.Value.Time, Attack.Value.Volume, Decay.Value.Volume, Attack.Value.Width, Decay.Value.Width, Sustain.Value.Time == 0);
            AddEnvelope(levels, Sustain.Value.Time, Decay.Value.Volume, Sustain.Value.Volume, Decay.Value.Width, Sustain.Value.Width, Release.Value.Time == 0);
            AddEnvelope(levels, Release.Value.Time, Sustain.Value.Volume, Release.Value.Volume, Sustain.Value.Width, Release.Value.Width, true);

            Value.Levels = levels;

            UpdateLevels();
        }

        private void AddEnvelope(List<Models.InstrumentStep> levels, int length, int startVolume, int nextVolume, int startWidth, int nextWidth, bool incEnd = false)
        {
            if (length <= 0)
                return;

            var volume = (double)startVolume;
            var volumeStep = (nextVolume - startVolume) / (double)length;

            var width = (double)startWidth;
            var widthStep = (nextWidth - startWidth) / (double)length;

            for(var i = 0; i < length; i++)
            {
                levels.Add(new Models.InstrumentStep { Position = levels.Count, Volume = (int)volume, Width = (int)width });
                volume += volumeStep;
                width += widthStep;
            }

            if (incEnd)
            {
                levels.Add(new Models.InstrumentStep { Position = levels.Count, Volume = nextVolume, Width = nextWidth });
            }
        }

        private void WaveType_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            Value.WaveType = (Models.WaveType)this.WaveType.SelectedIndex;
        }

        private void InstrumentName_TextChanged(object sender, TextChangedEventArgs e)
        {
            Value.Name = InstrumentName.Text;
        }

        private void Repeat_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (int.TryParse(Repeat.Text, out var newval)) 
            {
                Value.RepeatStart = newval;
            }
        }
    }
}
