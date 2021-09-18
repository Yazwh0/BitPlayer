using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Models;

namespace WinPlayer.Waveform
{
    class None : IVeraWaveform
    {
        public double Frequency { get; set; }
        public int NoteNumber { get; set; }
        public int Volume { get; set; }
        public int Width { get; set; }

        public WaveType WaveType => WaveType.None;

        public float GetNext()
        {
            return 0;
        }
    }
}
