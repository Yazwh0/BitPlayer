using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Command;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class FrequencyUp : ICommand
    {
        public short Parameters { get; set; }
        private double OriginalFrequency { get; set; }

        public void ApplyNext(IVeraWaveform generator)
        {
            OriginalFrequency = generator.Frequency;
            generator.Frequency += Parameters;
            generator.Frequency = Math.Max(generator.Frequency, 0xffff);
        }

        public void Remove(IVeraWaveform generator)
        {
             generator.Frequency = OriginalFrequency;
        }
    }
}
