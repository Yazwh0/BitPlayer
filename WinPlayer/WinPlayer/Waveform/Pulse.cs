using NAudio.Wave;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Models;

namespace WinPlayer.Waveform
{
    class Pulse : IVeraWaveform
    {
        public double Frequency { get; set; }
        private int _noteNumber { get; set; }
        public int NoteNumber
        {
            get => _noteNumber;
            set
            {
                _noteNumber = value;
                Frequency = FreqencyLookup.Lookup(NoteNumber).Frequency;
                if (_noteNumber == 0)
                {
                    cycle = CycleWidth / 2;
                }
            }
        }

        private int _volume = 63;
        public int Volume
        {
            get => _volume;
            set => _volume = Math.Min(value, 63);
        }

        private int _width = 63;
        public int Width { 
            get => _width;
            set => _width = Math.Min(value, 63);
        }

        private int cycle = 0;
        private readonly double _sampleRate;

        // one full cycle at this Frequency
        private int CycleWidth => (int)(1.0 / Frequency * _sampleRate);

        // When to change
        private int CycleChange => (int)(CycleWidth / 128.0 * Width) + 1;

        public WaveType WaveType => WaveType.Pulse;

        public Pulse(double sampleRate)
        {
            _sampleRate = sampleRate;
        }

        public float GetNext()
        {
            cycle++;
            int toPlay;

            if (cycle > CycleChange)
            {
                toPlay = 32 * VolumeLookup.Lookup(_volume);
            } 
            else 
            { 
                toPlay = -32 * VolumeLookup.Lookup(_volume);
            }

            if (cycle > CycleWidth)
                cycle = 0;

            return toPlay / 2048.0f;
        }
    }

    public interface IVeraWaveform: IWaveFormGenerator
    {
        public double Frequency { get; set; }
        public int NoteNumber { get; set; }
        public int Volume { get; set; }
        public int Width { get; set; }
        public Models.WaveType WaveType { get; }
    }

    public static class VeraWaveform
    {
        public static IVeraWaveform? GetGenerator(Models.WaveType waveType) =>
            waveType switch
            {
                Models.WaveType.None => null,
                Models.WaveType.Pulse => new Pulse(Globals.SampleRate),
                Models.WaveType.Triangle => new Triangle(Globals.SampleRate),
                Models.WaveType.Sawtooth => new Sawtooth(Globals.SampleRate),
                Models.WaveType.Noise => new Noise(Globals.SampleRate),
                _ => throw new NotImplementedException()
            };
    }

    public interface IWaveFormGenerator
    {
        float GetNext();
    }
}
