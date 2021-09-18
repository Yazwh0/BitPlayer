using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Command;
using WinPlayer.Models;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class SlideUpToNote : ICommand
    {
        public Note? Note { get; set; }
        public short Parameters { get; set; }

        private bool _initalised = false;
        private int _step = 0;
        private int _current = 0;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initalised)
            {
                _initalised = true;
                _step = ((ICommand)this).Parameters0;
                _current = ((ICommand)this).Parameters1;
            }

            if (_current != 0)
            {
                //Debug.WriteLine($"{FrequencyLookup.Lookup(generator.NoteNumber).Frequency}, {FrequencyLookup.FrequencySlide(_step > 1 ? generator.NoteNumber : generator.NoteNumber - 1)}, {_step}, {_current}, {FrequencyLookup.Lookup(generator.NoteNumber).Frequency + FrequencyLookup.FrequencySlide(_step > 1 ? generator.NoteNumber : generator.NoteNumber - 1) * _step * _current}");
                generator.Frequency = FrequencyLookup.Lookup(generator.NoteNumber).Frequency + FrequencyLookup.FrequencySlide(generator.NoteNumber) * _step * _current;
                _current--;
            }
            else
            {
                //Debug.WriteLine($"{FrequencyLookup.Lookup(generator.NoteNumber).Frequency}");
                generator.Frequency = FrequencyLookup.Lookup(generator.NoteNumber).Frequency;
            }

        }
    }
    public class SlideDownToNote : ICommand
    {
        public Note? Note { get; set; }
        public short Parameters { get; set; }

        private bool _initalised = false;
        private int _step = 0;
        private int _current = 0;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initalised)
            {
                _initalised = true;
                _step = ((ICommand)this).Parameters0;
                _current = ((ICommand)this).Parameters1;
            }

            if (_current != 0)
            {
                //Debug.WriteLine($"{FrequencyLookup.Lookup(generator.NoteNumber).Frequency}, {FrequencyLookup.FrequencySlide(_step > 1 ? generator.NoteNumber : generator.NoteNumber - 1)}, {_step}, {_current}, {FrequencyLookup.Lookup(generator.NoteNumber).Frequency + FrequencyLookup.FrequencySlide(_step > 1 ? generator.NoteNumber : generator.NoteNumber - 1) * _step * _current}");
                generator.Frequency = FrequencyLookup.Lookup(generator.NoteNumber).Frequency - FrequencyLookup.FrequencySlide(generator.NoteNumber) * _step * _current;
                _current--;
            }
            else
            {
                //Debug.WriteLine($"{FrequencyLookup.Lookup(generator.NoteNumber).Frequency}");
                generator.Frequency = FrequencyLookup.Lookup(generator.NoteNumber).Frequency;
            }

        }
    }
}
