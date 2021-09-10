using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class FrequencySlide : ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set; }

        private int _step = 0;
        private int _current = 0;
        private bool _initalised = false;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initalised)
            {
                _initalised = true;
                var param1 = ((ICommand)this).Parameters0;
                _step = param1 > 127 ? param1 - 256 : param1;
                _current = 0;
            }

            _current += _step;

            generator.Frequency = FrequencyLookup.Lookup(generator.NoteNumber).Frequency + FrequencyLookup.VeraToFreqency(_current);
            generator.Frequency = Math.Max(generator.Frequency, 0);
        }
    }
}
