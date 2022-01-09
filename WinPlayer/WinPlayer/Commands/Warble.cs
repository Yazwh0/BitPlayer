using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class Warble : ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set ; }

        private int _steps = 0;
        private int _changeCnt = 0;
        private double _baseFreq = 0;
        private int _framesPerStep = 0;
        private int _amplitude = 1;
        public bool _up = true;

        private bool _initialised = false;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initialised)
            {
                _framesPerStep = ((ICommand)this).Parameters1;
                _framesPerStep = _framesPerStep == 0 ? 1 : _framesPerStep;
                _framesPerStep = _framesPerStep > 7 ? 7 : _framesPerStep;
                _amplitude = ((ICommand)this).Parameters0;
                _amplitude = _amplitude == 0 ? 1 : _amplitude;
                _amplitude = _amplitude > 3 ? 3 : _amplitude; // cant go through a semi tone.
                _changeCnt = _framesPerStep;
                _steps = 0;
                _baseFreq = generator.Frequency;
                _up = true;
                _initialised = true;
            }

            if (_steps == 0)
            {
                generator.Frequency = FrequencyLookup.FrequencyStep(generator.NoteNumber, 0);
            } 
            else
            {
                var thisSteps = _steps >> 1;
                double freq;
                if (thisSteps > 0)
                {
                    freq = FrequencyLookup.FrequencyStep(generator.NoteNumber, _steps);
                } 
                else
                {
                    freq = FrequencyLookup.FrequencyStep(generator.NoteNumber-1, 4-thisSteps);
                }
                generator.Frequency = freq;
            }

            _changeCnt--;
            if (_changeCnt == 0)
            {
                _changeCnt = _framesPerStep;
                if (_up)
                {
                    _steps++;

                    if (_steps == _amplitude)
                        _up = false;
                } 
                else
                {
                    _steps--;

                    if (_steps == -_amplitude)
                        _up = true;                    
                }
            }
        }

        public void Remove(IVeraWaveform generator)
        {
            generator.Frequency = _baseFreq;
        }
    }
}
