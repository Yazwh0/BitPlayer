//#define EXPORTTOFILE
using NAudio.Wave;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Command;
using WinPlayer.Waveform;

namespace WinPlayer.Player
{
    public class SongPlayer : WaveProvider32
    {
        private readonly Models.Song _song;
        private int _timeIndex = 0;
        private int _patternIndex = 0;
        private int _lineIndex = 0;
        private int _frame = 0;

        private bool _firstLine = true;
        private bool _playPattern;

        private Models.Pattern _currentPattern;
        private Models.Note[] _currentNotes;
        private Models.Instrument?[] _currentInstruments;
        private IVeraWaveform?[] _currentWaveFormGenerators;
        private ICommand[] _effects;
        private int[] _currentLevelIndex;

        private float _multiplier = 1; // to try to normalise the volume

        private int FrameCount => Globals.SampleRate / 60;

        public SongPlayer(Models.Song song, int? patternNumber = null) : base(Globals.SampleRate, 1)
        {
            _song = song;

            if (patternNumber == null)
                _currentPattern = _song.Patterns[_song.Playlist[0]];
            else
                _currentPattern = _song.Patterns[patternNumber.Value];

            _playPattern = patternNumber != null;

            _currentInstruments = new Models.Instrument[16];
            _currentWaveFormGenerators = new IVeraWaveform[16];
            _currentNotes = new Models.Note[16];
            _effects = new ICommand[16];

            for (var i = 0; i < 16; i++)
            {
                if (_currentPattern.Tracks[i] == null)
                    _currentPattern.Tracks[i] = new Models.Track();

                _effects[i] = new Clear();
                _currentNotes[i] = _currentPattern.Tracks[i].Notes[_lineIndex];
                _currentInstruments[i] = _song.Instruments.FirstOrDefault(x => x.InstrumentNumber == _currentNotes[i].InstrumentNumber && _currentNotes[i].NoteNum != 0);
                _currentWaveFormGenerators[i] = VeraWaveform.GetGenerator(_currentInstruments[i]?.WaveType ?? Models.WaveType.None);
            }

            _currentLevelIndex = new int[16];

            var hasNotes = new bool[16];
            foreach(var p in _song.Patterns)
            {
                var idx = 0;
                foreach (var t in p.Tracks)
                {
                    if (hasNotes[idx])
                        continue;

                    foreach(var n in t.Notes)
                    {
                        if (n.NoteNum != 0)
                        {
                            hasNotes[idx] = true;

                            break;
                        }
                    }

                    idx++;
                }
            }

            _multiplier = 16.0f / hasNotes.Count(i => i);
        }


        public override int Read(float[] buffer, int offset, int count)
        {
            for (int index = 0; index < count; index++)
            {
                _timeIndex++;

                if (_timeIndex > FrameCount || _firstLine)
                {
                    NextFrame();
                    _timeIndex = 0;
                    _firstLine = false;
                }

                buffer[offset + index] = 0;

                for (int i = _currentWaveFormGenerators.GetLowerBound(0); i < _currentWaveFormGenerators.GetUpperBound(0); i++)
                {
                    var generator = _currentWaveFormGenerators[i];

                    if (generator == null)
                        continue;

/*                    if (_timeIndex == 0)
                    {
                        _effects[i].ApplyNext(generator);
                    }
*/
                    var toAdd = generator.GetNext();

                    buffer[offset + index] += toAdd;
                }

                buffer[offset + index] = buffer[offset + index] / 16 * _multiplier;
            }

#if EXPORTTOFILE
                WriteDebug(buffer);
#endif

            return count;
        }

        private void WriteDebug(float[] buffer)
        {
            var sb = new StringBuilder();

            for (var i = buffer.GetLowerBound(0); i < buffer.GetUpperBound(0); i++)
                {
                sb.AppendLine(buffer[i].ToString());
            }

            if (File.Exists("debug.csv"))
                File.Delete("debug.csv");

            File.WriteAllText("debug.csv", sb.ToString());
        }

        private void NextFrame()
        {
            _frame++;

            if (_frame > _currentPattern.Speed - 1 || _firstLine)
            {
                NextLine();
                _frame = 0;
            }

            // set volume
            for (var i = _currentWaveFormGenerators.GetLowerBound(0); i < _currentWaveFormGenerators.GetUpperBound(0); i++)
            {
                var instrument = _currentInstruments[i];

                if (instrument == null || _currentLevelIndex[i] >= instrument.Levels.Count)
                {
                    if (instrument != null && instrument.RepeatStart != -1)
                    {
                        _currentLevelIndex[i] = instrument.RepeatStart;
                        SetVolume(i, instrument.Levels[_currentLevelIndex[i]++], _effects[i]);
                    }
                    continue;
                }

                SetVolume(i, instrument.Levels[_currentLevelIndex[i]++], _effects[i]);
            }
        }

        private void SetVolume(int index, Models.InstrumentStep step, ICommand? command)
        {
            var generator = _currentWaveFormGenerators[index];

            if (generator == null)
                return;

            generator.Volume = step.Volume;
            generator.Width = step.Width;
            if (_currentNotes[index] != null && _currentNotes[index].NoteNum != 0)
                generator.NoteNumber = _currentNotes[index].NoteNum + step.NoteAdjust;

            if (command != null)
            {
                command.ApplyNext(generator);
            }
        }

        private Models.Instrument? GetInstrument(int index, Models.Note? note)
        {
            if (note == null || note.NoteNum == 0)
                return null;

            var instrument = _currentInstruments[index];

            if (instrument != null && instrument.InstrumentNumber == note.InstrumentNumber)
                return _currentInstruments[index];

            return _song.Instruments.First(x => x.InstrumentNumber == note.InstrumentNumber);
        }

        private void NextLine()
        {
            _lineIndex++;
            Debug.WriteLine($"NextLine {_lineIndex}");

            if (_lineIndex >= _currentPattern.TrackLength || _firstLine)
            {
                NextPattern();
                _lineIndex = 0;
            }

            for (var i = _currentWaveFormGenerators.GetLowerBound(0); i < _currentWaveFormGenerators.GetUpperBound(0); i++)
            {
                var note = _currentPattern.Tracks[i].Notes[_lineIndex].Clone();

                if (note.NoteNum != 0)
                {
                    _currentNotes[i] = note;
                    Debug.WriteLine($"Note {note.NoteNum}");

                    _currentLevelIndex[i] = 0;

                    var instrument = GetInstrument(i, note);
                    _currentInstruments[i] = instrument;

                    var generator = GetWaveFormGenerator(i, instrument?.WaveType ?? Models.WaveType.None);
                    _currentWaveFormGenerators[i] = generator;

                    if (generator != null && instrument != null)
                    {
                        generator.Frequency = FrequencyLookup.Lookup(note.NoteNum).Frequency;
                    } 

                    _effects[i] = CommandFactory.GetCommand(note.Command, note.CommandParam, note);
                } 
                else if (note.Command != Commands.None)
                {
                    _effects[i] = CommandFactory.GetCommand(note.Command, note.CommandParam, _currentNotes[i]);
                }
            }
        }


        private IVeraWaveform? GetWaveFormGenerator(int index, Models.WaveType waveType)
        {
            var generator = _currentWaveFormGenerators[index];

            if (generator != null && generator.WaveType == waveType)
                return generator;

            return VeraWaveform.GetGenerator(waveType);            
        }

        private void NextPattern()
        {
            if (_playPattern)
                return;

            _patternIndex++;
            Debug.WriteLine($"NextPattern {_patternIndex}");

            if (_patternIndex >= _song.Playlist.Count || _firstLine)
            {
                _patternIndex = 0;
            }

            _currentPattern = _song.Patterns[_song.Playlist[_patternIndex]];
        }
    }
}
