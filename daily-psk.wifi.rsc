#!rsc by RouterOS
# RouterOS script: daily-psk.wifi
# Copyright (c) 2013-2024 Christian Hesse <mail@eworm.de>
#                         Michael Gisbers <michael@gisbers.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# requires RouterOS, version=7.13
#
# update daily PSK (pre shared key)
# https://git.eworm.de/cgit/routeros-scripts/about/doc/daily-psk.md
#
# !! Do not edit this file, it is generated from template!

:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:do {
  :local ScriptName [ :jobname ];

  :global DailyPskMatchComment;
  :global DailyPskQrCodeUrl;
  :global Identity;

  :global FormatLine;
  :global LogPrint;
  :global RequiredRouterOS;
  :global ScriptLock;
  :global SendNotification2;
  :global SymbolForNotification;
  :global UrlEncode;
  :global WaitForFile;
  :global WaitFullyConnected;

  :if ([ $ScriptLock $ScriptName ] = false) do={
    :error false;
  }
  $WaitFullyConnected;

  # return pseudo-random string for PSK
  :local GeneratePSK do={
    :local Date [ :tostr $1 ];

    :global DailyPskSecrets;

    :global ParseDate;

    :set Date [ $ParseDate $Date ];

    :local A ((14 - ($Date->"month")) / 12);
    :local B (($Date->"year") - $A);
    :local C (($Date->"month") + 12 * $A - 2);
    :local WeekDay (7000 + ($Date->"day") + $B + ($B / 4) - ($B / 100) + ($B / 400) + ((31 * $C) / 12));
    :set WeekDay ($WeekDay - (($WeekDay / 7) * 7));

    :return (($DailyPskSecrets->0->(($Date->"day") - 1)) . \
      ($DailyPskSecrets->1->(($Date->"month") - 1)) . \
      ($DailyPskSecrets->2->$WeekDay));
  }

  :local Seen ({});
  :local Date [ /system/clock/get date ];
  :local NewPsk [ $GeneratePSK $Date ];

  :foreach AccList in=[ /interface/wifi/access-list/find where comment~$DailyPskMatchComment ] do={
    :local SsidRegExp [ /interface/wifi/access-list/get $AccList ssid-regexp ];
    :local Configuration ([ /interface/wifi/configuration/find where ssid~$SsidRegExp ]->0);
    :local Ssid [ /interface/wifi/configuration/get $Configuration ssid ];
    :local OldPsk [ /interface/wifi/access-list/get $AccList passphrase ];
    :local Skip 0;

    :if ($NewPsk != $OldPsk) do={
      $LogPrint info $ScriptName ("Updating daily PSK for " . $Ssid . " to " . $NewPsk . " (was " . $OldPsk . ")");
      /interface/wifi/access-list/set $AccList passphrase=$NewPsk;

      :if ([ $RequiredRouterOS $ScriptName "7.15beta8" false ] = false || [ :len [ /interface/wifi/find where configuration.ssid=$Ssid !disabled ] ] > 0) do={
        :if ($Seen->$Ssid = 1) do={
          $LogPrint debug $ScriptName ("Already sent a mail for SSID " . $Ssid . ", skipping.");
        } else={
          :local Link ($DailyPskQrCodeUrl . \
              "?scale=8&level=1&ssid=" . [ $UrlEncode $Ssid ] . "&pass=" . [ $UrlEncode $NewPsk ]);
          $SendNotification2 ({ origin=$ScriptName; \
            subject=([ $SymbolForNotification "calendar" ] . "daily PSK " . $Ssid); \
            message=("This is the daily PSK on " . $Identity . ":\n\n" . \
              [ $FormatLine "SSID" $Ssid ] . "\n" . \
              [ $FormatLine "PSK" $NewPsk ] . "\n" . \
              [ $FormatLine "Date" $Date ] . "\n\n" . \
              "A client device specific rule must not exist!"); link=$Link });
          :set ($Seen->$Ssid) 1;
        }
      }
    }
  }
} on-error={ }
