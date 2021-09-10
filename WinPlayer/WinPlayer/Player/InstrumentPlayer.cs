using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using NAudio.Wave;
using WinPlayer.Command;
using WinPlayer.Models;
using WinPlayer.Waveform;

namespace WinPlayer
{
    public class InstrumentPlayer : WaveProvider32
    {
        public readonly Models.Instrument Instrument;

        private IVeraWaveform? _generator;
        private ICommand _command;
        private int _currentLevelIndex;
        private int _timeIndex = 0;
        private int _noteNumber = 0;

        private int FrameCount => Globals.SampleRate / 60;

        public InstrumentPlayer(Models.Instrument instrument, Note note) : base(Globals.SampleRate, 1)
        {
            if (instrument == null)
                throw new ArgumentException(nameof(instrument));

            Instrument = instrument;

            _generator =
                VeraWaveform.GetGenerator(Instrument?.WaveType ?? Models.WaveType.None);

            if (_generator == null)
                return; ;

            _generator.Width = instrument.PulseWidth;
            _generator.NoteNumber = note.NoteNum;
            _noteNumber = note.NoteNum;

            _command = CommandFactory.GetCommand(note.Command, note.CommandParam, note);
        }

        public override int Read(float[] buffer, int offset, int count)
        {
            try
            {
                for (int index = 0; index < count; index++)
                {
                    buffer[offset + index] = _generator?.GetNext() ?? 0 / 4;

                    _timeIndex++;

                    if (_timeIndex > FrameCount)
                    {
                        NextFrame();
                        _command.ApplyNext(_generator);
                        _timeIndex = 0;
                    }
                }
            } 
            catch(Exception e)
            {
                Debug.WriteLine(e.Message);
            }

            Debug.WriteLine(count);
            return count;
        }

        private void NextFrame()
        {
            // set volume
            if (_currentLevelIndex >= Instrument.Levels.Count)
            {
                if (Instrument.RepeatStart != -1)
                {
                    _currentLevelIndex = Instrument.RepeatStart;
                    if (_currentLevelIndex > Instrument.Levels.Count)
                        _currentLevelIndex = Instrument.Levels.Count;

                    SetVolume(Instrument.Levels[_currentLevelIndex++]);
                }

                return;
            }

            SetVolume(Instrument.Levels[_currentLevelIndex++]);
        }

        private void SetVolume(Models.InstrumentStep step)
        {
            var generator = _generator;

            if (generator == null)
                return;

            generator.Volume = step.Volume ;
            generator.Width = step.Width ;
            generator.NoteNumber = _noteNumber + step.NoteAdjust;
        }
    }
}
