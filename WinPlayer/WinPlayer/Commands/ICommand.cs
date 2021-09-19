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
        Silence,
        FrequencySlideUp,
        FrequencySlideDown
    }

    public static class CommandFactory
    {
        public static ICommand GetCommand(Commands effect, short parameter, Models.Note note)
        {
            ICommand toReturn = effect switch
            {
                Commands.FrequencySlide => new Clear(),
                //Commands.Warble => new Warble(),
                Commands.ClearCommand => new Clear(),
                //Commands.NoteSlide => new NoteSlide(),
                Commands.SlideUpToNote => new SlideUpToNote(),
                Commands.SlideDownToNote => new SlideDownToNote(),
                Commands.PitchShiftUp => new PitchShiftUp(),
                Commands.PitchShiftDown => new PitchShiftDown(),
                Commands.Silence => new Silence(),
                Commands.FrequencySlideUp => new FrequencySlideUp(),
                Commands.FrequencySlideDown => new FrequencySlideDown(),
                _ => new Clear()
            };

            toReturn.Parameters = parameter;
            toReturn.Note = note;
            return toReturn;
        }

        public static string GetDisplay(Commands effect) => effect switch
        {
            Commands.None => "",
            //Commands.Warble => "Warble",
            //Commands.NoteSlide => "Nte Sl",
            Commands.ClearCommand => "Clear",
            Commands.SlideUpToNote => "Sl Nte Up",
            Commands.SlideDownToNote => "Sl Nte Dn",
            Commands.PitchShiftUp => "Pch Sh Up",
            Commands.PitchShiftDown => "Pch Sh Dn",
            Commands.Silence => "Silence",
            Commands.FrequencySlideUp => "Freq Sl Up",
            Commands.FrequencySlideDown => "Freq Sl Dn",
            _ => "??"
        };
    }
}
