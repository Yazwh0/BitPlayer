using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Models;

namespace WinPlayer.Exporters
{
    public class Cc65Asm : IExporter
    {
        public string ExporterName => "BitPlayer (CC65 ASM)";
        private double Divisor = 48828.125 / Math.Pow(2, 17);

        private enum CodeParts 
        {
            Instruments,
            InstrumentPlay,
            InstrumentSwitch,
            InstrumentInit,
            InstrumentLength,
            Patterns,
            PatternInit,
            Tempo,
            PlayListLength,
            PatternPlayList,
            PatternSize,
            PatternJumpTable,
            PatternWidth,
            NoteNumLookup,
            NoteSlideLookup,
            CommandJumpTable,
            HasCommands,
            NoteSlideLow,
            NoteSlideMid,
            NoteSlideHigh
        }

        public async Task Export(Song song, string filename)
        {
            Dictionary<CodeParts, StringBuilder> output = new();

            AddInstruments(song, output);
            AddPatterns(song, output);
            AddSongDetails(song, output);
            AddStaticData(output);

            var toSave = ConstructFile(output);

            await File.WriteAllTextAsync(filename, toSave);
        }

        private void AddStaticData(Dictionary<CodeParts, StringBuilder> output)
        {
            var noteNumLookupSb = new StringBuilder();
            output.Add(CodeParts.NoteNumLookup, noteNumLookupSb);

            var noteSlideLookupSb = new StringBuilder();
            output.Add(CodeParts.NoteSlideLookup, noteSlideLookupSb);

            var noteSlideLowSb = new StringBuilder();
            output.Add(CodeParts.NoteSlideLow, noteSlideLowSb);
            var noteSlideMidSb = new StringBuilder();
            output.Add(CodeParts.NoteSlideMid, noteSlideMidSb);
            var noteSlideHighSb = new StringBuilder();
            output.Add(CodeParts.NoteSlideHigh, noteSlideHighSb);

            // starts at 21
            for (var i = 1; i <= 128; i++)
            {
                if (i < 21)
                {
                    noteNumLookupSb.AppendLine($"\t.word $0000");
                }
                else
                {
                    noteNumLookupSb.AppendLine($"\t.word ${FrequencyLookup.FrequencyToVera(FrequencyLookup.Lookup(i).Frequency):X4}");
                }
                if (i < 22)
                {
                    noteSlideLookupSb.AppendLine($"\t.word $0000");
                    noteSlideLowSb.AppendLine($"\t.word $0000");
                    noteSlideMidSb.AppendLine($"\t.word $0000");
                    noteSlideHighSb.AppendLine($"\t.word $0000");
                }
                else
                {
                    noteSlideLookupSb.AppendLine($"\t.word ${FrequencyLookup.FrequencyToVera(FrequencyLookup.FrequencySlide(i)):X4}");
                    noteSlideLowSb.AppendLine($"\t.word ${FrequencyLookup.FrequencyToVera(FrequencyLookup.FrequencyStep(i, 1)):X4}");
                    noteSlideMidSb.AppendLine($"\t.word ${FrequencyLookup.FrequencyToVera(FrequencyLookup.FrequencyStep(i, 2)):X4}");
                    noteSlideHighSb.AppendLine($"\t.word ${FrequencyLookup.FrequencyToVera(FrequencyLookup.FrequencyStep(i, 3)):X4}");
                }
            }
        }

        private string ConstructFile(Dictionary<CodeParts, StringBuilder> output)
        {
            var input = File.ReadAllText(Globals.Settings.ExportTemplateName);

            foreach(var kv in output)
            {
                var toFind = $"###{kv.Key.ToString()}";
                input = input.Replace(toFind, output[kv.Key].ToString());
            }

            return input;
        }

        private void AddSongDetails(Song song, Dictionary<CodeParts, StringBuilder> output) {
            var frameSb = new StringBuilder();
            output.Add(CodeParts.Tempo, frameSb);

           // frameSb.Append($"${song.Tempo:X2}");

            var patternSb = new StringBuilder();
            output.Add(CodeParts.PlayListLength, patternSb);

            patternSb.Append($"${song.Playlist.Count:X2}");
            
            var playListSb = new StringBuilder();
            output.Add(CodeParts.PatternPlayList, playListSb);
            playListSb.AppendLine($"pattern_playlist:");

            var playList = song.Playlist.ToArray().Reverse();

            foreach (var p in playList) // go backwards to make indexing easier
            {
                playListSb.AppendLine($"\t.byte ${p:X2}");
            }
        }

        private void AddPatterns(Song song, Dictionary<CodeParts, StringBuilder> output)
        {
            var patternInitSb = new StringBuilder();
            output.Add(CodeParts.PatternInit, patternInitSb);

            var patternsSb = new StringBuilder();
            output.Add(CodeParts.Patterns, patternsSb);

            patternInitSb.AppendLine("patterns:");

            var patternJumpTableSb = new StringBuilder();
            output.Add(CodeParts.PatternJumpTable, patternJumpTableSb);

            var patternWidthSb = new StringBuilder();
            output.Add(CodeParts.PatternWidth, patternWidthSb);

            var commandsUsed = new Dictionary<Command.Commands, int>();

            var maxPattern = song.Patterns.Select(i => i.Number).Max();
            for (var i = 0; i <= maxPattern; i++)
            {
                if (song.Patterns.Any(p => p.Number == i))
                {
                    patternInitSb.AppendLine($"\t.word pattern_{i}");
                }
                else
                {
                    patternInitSb.AppendLine($"\t.word $0000");
                }
                patternJumpTableSb.AppendLine($"\t.word pattern_{i}_init");
            }

            // first have to find the distinct commands used:
            var cmdIdx = 1;
            foreach(var p in song.Patterns)
            {
                foreach(var t in p.Tracks)
                {
                    foreach(var n in t.Notes)
                    {
                        if (n.Command != Command.Commands.None)
                        {
                            if (!commandsUsed.ContainsKey(n.Command))
                            {
                                commandsUsed.Add(n.Command, cmdIdx++);
                            }
                        }
                    }
                }
            }

            var hasCommandsSb = new StringBuilder();
            output.Add(CodeParts.HasCommands, hasCommandsSb);

            hasCommandsSb.Append(commandsUsed.Any() ? "1" : "0");

            var commandJumpTableSb = new StringBuilder();
            output.Add(CodeParts.CommandJumpTable, commandJumpTableSb);
            
            foreach(var cmd in commandsUsed)
            {
                commandJumpTableSb.AppendLine($"\t.word command_{cmd.Key.ToString().ToLower()}");
            }

            patternsSb.AppendLine($"pattern_data:");

            int totalSize = 0;
            int maxWidth = 0;
            foreach (var pattern in song.Patterns)
            {
                var nextLine = 0;
                var firstNote = true;
                patternsSb.AppendLine($"pattern_{pattern.Number}:");
                var patternSize = 0;
                var firstLine = 0;

                for (var noteNum = 0; noteNum < pattern.TrackLength; noteNum++) {
                    var firstItem = true;
                    var firstItemCounter = 0;
                    var hasItems = false;
                    for (var trackNum = 0; trackNum < pattern.Tracks.Count; trackNum++)
                    {
                        var note = pattern.Tracks[trackNum].Notes[noteNum];

                        if (note.Command != Command.Commands.None || note.NoteNum != 0)
                        {
                            if (trackNum > maxWidth)
                                maxWidth = trackNum;

                            hasItems = true;
                            if (firstItem)
                            {
                                if (firstNote)
                                {
                                    //todo: store this for the pattern init
                                    firstNote = false;
                                    patternsSb.AppendLine();
                                    firstLine = noteNum + 1;
                                }
                                else
                                {
                                    patternsSb.AppendLine($"\t.byte ${nextLine:X2}\t; next line count\n");
                                    patternSize++;
                                    nextLine = 0;
                                }
                                patternsSb.AppendLine($"\t.byte ${firstItemCounter:X2}\t; first voice is {firstItemCounter}");
                                patternSize++;
                            }
                            else
                            {
                                patternsSb.AppendLine($"\t.byte ${firstItemCounter:X2}\t; steps to next voice");
                                patternSize++;
                            }

                            if (note.NoteNum < 1)
                            {
                                patternsSb.AppendLine("\t.byte $00\t; no note");
                            }
                            else
                            {
                                patternsSb.AppendLine($"\t.byte ${(note.NoteNum - 1) * 2:X2}\t; Note {note.NoteNum} (-1*2) {note.NoteStr} - Vera {FrequencyLookup.FrequencyToVera(FrequencyLookup.Lookup(note.NoteNum).Frequency):X4}");
                            }
                            patternSize += 1;

                            if (note.NoteNum > 1)
                            {
                                patternsSb.AppendLine($"\t.byte ${note.InstrumentNumber * 2:X2}\t; Instrument {note.InstrumentNumber}");
                                patternSize += 1;
                            }

                            if (note.Command == Command.Commands.None)
                            {
                                patternsSb.AppendLine("\t.byte $00\t; No command");
                                patternSize++;
                            }
                            else
                            {
                                patternsSb.AppendLine($"\t.byte ${commandsUsed[note.Command] * 2:X2}\t; {note.Command.ToString()}");
                                patternsSb.AppendLine($"\t.word ${note.CommandParam:X4}\t;");
                                patternSize += 3;
                            }

                            firstItemCounter = 0;
                            firstItem = false;
                        } 
                        else
                        {
                            firstItemCounter++;
                        }
                    }
                    if (hasItems)
                    {
                        patternsSb.AppendLine($"\t.byte $ff\t; no more for this line.");
                        patternSize++;
                    }

                    nextLine++;
                }
                patternsSb.AppendLine($"\t.byte $ff\t; pattern done.");
                patternSize++;
                patternsSb.AppendLine($"; -- size: {patternSize} bytes.");

                patternJumpTableSb.AppendLine();
                patternJumpTableSb.AppendLine($"pattern_{pattern.Number}_init:");
                patternJumpTableSb.AppendLine($"\tlda #(^(vh * $10000 + vm * $100 + vl + {totalSize})) + $10");
                patternJumpTableSb.AppendLine($"\tsta PATTERN_POS_H");
                patternJumpTableSb.AppendLine($"\tlda #>(vh * $10000 + vm * $100 + vl + {totalSize})");
                patternJumpTableSb.AppendLine($"\tsta PATTERN_POS_M");
                patternJumpTableSb.AppendLine($"\tlda #<(vh * $10000 + vm * $100 + vl + {totalSize})");
                patternJumpTableSb.AppendLine($"\tsta PATTERN_POS_L");
                patternJumpTableSb.AppendLine($"\tlda #${firstLine:X2} ; first line is {firstLine}");
                patternJumpTableSb.AppendLine($"\tsta NEXT_LINE_COUNTER");
                patternJumpTableSb.AppendLine($"\tlda #${pattern.TrackLength:X2} ; this pattern is {pattern.TrackLength} lines long");
                patternJumpTableSb.AppendLine($"\tsta LINE_INDEX");
                patternJumpTableSb.AppendLine($"\tlda #${pattern.Speed:X2} ; tempo");
                patternJumpTableSb.AppendLine($"\tsta next_line+1 ; modify reset code");
                patternJumpTableSb.AppendLine($"\tsta FRAME_INDEX");

                patternJumpTableSb.AppendLine($"\tjmp play_next");

                totalSize += patternSize;
            }
            patternsSb.AppendLine($"; -- total size: {totalSize} bytes.");

            var patternSizeSb = new StringBuilder();
            output.Add(CodeParts.PatternSize, patternSizeSb);

            patternSizeSb.Append($"${totalSize:X4}");
            patternWidthSb.Append($"{maxWidth+1}");
        }

        /*private int FrequencyToVera(double frequency)
        {
            return (int)(frequency / (48828.125 / Math.Pow(2, 17)));
        }*/

        private void AddInstruments(Song song, Dictionary<CodeParts, StringBuilder> output)
        {
            var maxNum = song.Instruments.Select(i => i.InstrumentNumber).Max(); ;

            var insInc = new bool[maxNum + 1];

            var instrumentsSb = new StringBuilder();
            //var instrumentsPlaySb = new StringBuilder();
            var instrumentSwitchSb = new StringBuilder();
            var instrumentInitSb = new StringBuilder();
            var instrumentLengthSb = new StringBuilder();

            output.Add(CodeParts.Instruments, instrumentsSb);
            //output.Add(CodeParts.InstrumentPlay, instrumentsPlaySb);
            output.Add(CodeParts.InstrumentSwitch, instrumentSwitchSb);
            output.Add(CodeParts.InstrumentInit, instrumentInitSb);
            output.Add(CodeParts.InstrumentLength, instrumentLengthSb);


            instrumentInitSb.AppendLine("instrument_init:");

            foreach (var pattern in song.Patterns)
            {
                foreach (var track in pattern.Tracks)
                {
                    foreach(var note in track.Notes)
                    {
                        if (note.NoteNum != 0)
                        {
                            insInc[note.InstrumentNumber] = true;
                        }
                    }
                }   
            }

       //     var instruments = song.Instruments.Where(i => insInc[i.InstrumentNumber]).ToArray();

            instrumentSwitchSb.AppendLine($"instruments_play:");

            int cnt = 0;
            foreach (var i in insInc)
            {
                if (i)
                {
                    instrumentSwitchSb.AppendLine($"\t.word instrument_{cnt}");
                }
                else
                {
                    instrumentSwitchSb.AppendLine($"\t.word $0000");
                }

                cnt++;
            }

            instrumentLengthSb.AppendLine($"instrument_length:");
            var pos = 0;
            foreach (var instrument in song.Instruments)
            {
                if (!insInc[instrument.InstrumentNumber])
                {
                    instrumentLengthSb.AppendLine($"\t.byte $00, $00");
                    continue;
                }

                instrumentsSb.AppendLine($"instrument_{instrument.InstrumentNumber}:");

                var l = instrument.Levels.ToArray().Reverse();
                foreach(var part in l)
                {
                    var adj = (part.NoteAdjust * 2).ToString("X2");
                    adj = adj.Substring(adj.Length - 2, 2);
                    instrumentsSb.AppendLine($"\t.byte ${(((int)instrument.WaveType - 1) << 6) + Math.Max(63, part.Width):X2}, ${part.Volume | 0b1100_0000:X2}, ${adj}; Width {part.Width} + Wave {instrument.WaveType}, Volume {part.Volume}, NoteAdj {part.NoteAdjust}");
                }

                instrumentInitSb.AppendLine($"instrument_{instrument.InstrumentNumber}_init:");

                instrumentLengthSb.Append($"\t.byte ${instrument.Levels.Count * 3 - 1:X2}, ");
                
                if (instrument.RepeatStart == -1)
                {
                    instrumentLengthSb.Append("$00");
                }
                else
                    instrumentLengthSb.Append($"${(instrument.Levels.Count - instrument.RepeatStart) * 3 - 1:X2}");
                {
                }
                instrumentLengthSb.AppendLine($" ; {instrument.Levels.Count} steps, {instrument.RepeatStart} repeat");

                pos++;

                //instrumentsPlaySb.AppendLine();
                instrumentInitSb.AppendLine();
            }
        }
    }
}
