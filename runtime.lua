if Controls.Port.Value == 0 then
  Controls.Port.Value = 8080
end

Controls["Connection Status"].Value = 0
Controls["Status Text"].String = "Not connected"
