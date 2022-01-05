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
                _shift = ((ICommand)this).Parameters0;
            }

            generator.Frequency = FrequencyLookup.FrequencyStep(generator.NoteNumber, _shift);
        }
    }

    public class PitchShiftDown : ICommand
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
                _shift = ((ICommand)this).Parameters0;
            }

            generator.Frequency = FrequencyLookup.FrequencyStep(generator.NoteNumber - 1, 4- _shift);
        }
    }

    public class SetNoteNum : ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set; }

        public void ApplyNext(IVeraWaveform generator)
        {
            var noteNum = ((ICommand)this).Parameters0;
            generator.Frequency = FrequencyLookup.FrequencyStep(noteNum, 0);
            Note.NoteNum = noteNum;
        }
    }
}
