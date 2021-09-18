using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class PitchShiftUp : ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set; }

        private int _shift = 0;
        private bool _initalised = false;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initalised)
            {
                _initalised = true;
                var param1 = ((ICommand)this).Parameters0;
                _shift = param1; //param1 > 127 ? param1 - 256 : param1;
            }

            generator.Frequency = FrequencyLookup.Lookup(generator.NoteNumber).Frequency + FrequencyLookup.FrequencySlide(generator.NoteNumber) * _shift;

        }
    }
}
