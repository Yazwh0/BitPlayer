using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WinPlayer.Command
{
    public interface ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set; }
        public byte Parameters0 => (byte)(Parameters & 255);
        public byte Parameters1 => (byte)(Parameters >> 8);

        public void ApplyNext(Waveform.IVeraWaveform generator);
   //     public void Remove(Waveform.IVeraWaveform generator);
    }

    public enum Commands
    {
        None,
        ClearCommand,
        FrequencySlide,
        SlideUpToNote,
        SlideDownToNote,
        PitchShiftUp,
        PitchShiftDown,
        Silence
    }

    public static class CommandFactory
    {
        public static ICommand GetCommand(Commands effect, short parameter, Models.Note note)
        {
            ICommand toReturn = effect switch
            {
                Commands.FrequencySlide => new FrequencySlide(),
                //Commands.Warble => new Warble(),
                Commands.ClearCommand => new NoEffect(),
                //Commands.NoteSlide => new NoteSlide(),
                Commands.SlideUpToNote => new SlideUpToNote(),
                Commands.SlideDownToNote => new SlideDownToNote(),
                Commands.PitchShiftUp => new PitchShiftUp(),
                Commands.Silence => new Silence(),
                _ => new NoEffect()
            };

            toReturn.Parameters = parameter;
            toReturn.Note = note;
            return toReturn;
        }

        public static string GetDisplay(Commands effect) => effect switch
        {
            Commands.None => "",
            Commands.FrequencySlide => "Fq Sl",
            //Commands.Warble => "Warble",
            //Commands.NoteSlide => "Nte Sl",
            Commands.SlideUpToNote => "Sl Nte Up",
            Commands.SlideDownToNote => "Sl Nte Dn",
            Commands.PitchShiftUp => "Pch Sh Up",
            Commands.Silence => "Silence",
            _ => "??"
        };
    }
}
