using NAudio.Wave;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;

namespace WinPlayer
{
    public static class Globals
    {
        public const int SampleRate = 48000; // Veras base frequency 828

        //public static InstrumentPartPlayer? Player;
        public static WaveOut WaveOut = new WaveOut();

        public static IInputSource? InputSource;
        //public const int PatternLength = 64;

        public static WriteableBitmap? Visualiser;

        public static Settings Settings = new Settings();

        public static string SettingsFileName = "usersettings.json";

        public static Exporters.IExporter Exporter { get; } = new Exporters.Cc65Asm();

        public static IWavePlayer? _player = null;

    }


    public class Settings
    {
        public string AutoSaveFileName = "autosave.mod.json";
        public string SongFileName = "song.mod.json";
        public string ExportFileName = "export.asm";
        public string ExportTemplateName = @"D:\Documents\Source\Player\src\playertemplate.asm";
        public string X16RunFileName = @"D:\Documents\Source\Player\build.ps1";
    }
}
