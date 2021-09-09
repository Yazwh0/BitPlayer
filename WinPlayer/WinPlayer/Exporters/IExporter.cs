using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WinPlayer.Exporters
{
    public interface IExporter
    {
        public Task Export(Models.Song song, string filename);

        public string ExporterName { get; }
    }
}
