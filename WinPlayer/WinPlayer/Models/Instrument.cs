using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WinPlayer.Models
{
    public enum WaveType
    {
        None,
        Pulse,
        Sawtooth,
        Triangle,
        Noise
    }

    public class Instrument
    {
        public int InstrumentNumber { get; set; }
        public string Name { get; set; } = "Instrument";

        [JsonIgnore]
        public string DisplayName => $"{InstrumentNumber:X2} {Name}";

        public int Length { get; set; }

        public WaveType WaveType { get; set; }

        public Envelope? StartEnvelope { get; set; }
        public Envelope? AttackEnvelope { get; set; }
        public Envelope? DecayEnvelope { get; set; }
        public Envelope? SustainEnvelope { get; set; }
        public Envelope? ReleaseEnvelope { get; set; }

        public int RepeatStart { get; set; } = -1;

        public int NoteAdjust { get; set; }
        public int PulseWidth { get; set; }

        public List<InstrumentStep> Levels { get; set; } = new List<InstrumentStep>();

        public Instrument()
        {
        }
    }

    public class InstrumentStep
    { 
        public int Position { get; set; }
        public int Volume { get; set; }
        public int Width { get; set; }
        public int NoteAdjust { get; set; }
    }
}
