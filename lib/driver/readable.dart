import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_buffer/dart_buffer.dart';
import '../log.dart';

import '../common.dart';

abstract class Message {
  final MessageHeader header;

  Message(this.header);

  @override
  String toString() => "Message: ${header.type}";
}

class UnknownMessage extends Message {
  final ByteData? data;

  UnknownMessage(super.header, this.data);

  @override
  String toString() =>
      "UnknownMessage: ${header.type}, data length: ${data?.lengthInBytes}";
}

class Command extends Message {
  late final CommandMapping value;

  Command(super.header, ByteData data) {
    value = CommandMapping.fromId(BufferReader(data).getUInt32());
  }

  @override
  String toString() => "Command: ${value.name}";
}

class ManufacturerInfo extends Message {
  late final int a;
  late final int b;

  ManufacturerInfo(super.header, ByteData data) {
    final reader = BufferReader(data);

    a = reader.getUInt32();
    a = reader.getUInt32();
  }

  @override
  String toString() => "ManufacturerInfo: a=$a, b=$b";
}

class SoftwareVersion extends Message {
  late final String version;

  SoftwareVersion(super.header, ByteData data) {
    version = ascii.decode(data.buffer.asUint8List(), allowInvalid: true);
  }

  @override
  String toString() => "SoftwareVersion: $version";
}

class BluetoothAddress extends Message {
  late final String address;

  BluetoothAddress(super.header, ByteData data) {
    address = ascii.decode(data.buffer.asUint8List(), allowInvalid: true);
  }

  @override
  String toString() => "BluetoothAddress: $address";
}

class BluetoothPIN extends Message {
  late final String pin;

  BluetoothPIN(super.header, ByteData data) {
    pin = ascii.decode(data.buffer.asUint8List(), allowInvalid: true);
  }

  @override
  String toString() => "BluetoothPIN: $pin";
}

class BluetoothDeviceName extends Message {
  late final String name;

  BluetoothDeviceName(super.header, ByteData data) {
    name = ascii.decode(data.buffer.asUint8List(), allowInvalid: true);
  }

  @override
  String toString() => "BluetoothDeviceName: $name";
}

class WifiDeviceName extends Message {
  late final String name;

  WifiDeviceName(super.header, ByteData data) {
    name = ascii.decode(data.buffer.asUint8List(), allowInvalid: true);
  }

  @override
  String toString() => "WifiDeviceName: $name";
}

class HiCarLink extends Message {
  late final String link;

  HiCarLink(super.header, ByteData data) {
    link = ascii.decode(data.buffer.asUint8List(), allowInvalid: true);
  }

  @override
  String toString() => "HiCarLink: $link";
}

class BluetoothPairedList extends Message {
  late final String data;

  BluetoothPairedList(super.header, ByteData buf) {
    data = ascii.decode(buf.buffer.asUint8List(), allowInvalid: true);
  }

  @override
  String toString() => "BluetoothPairedList: $data";
}

class NetworkMacAddress extends Message {
  late final String macAddress;

  NetworkMacAddress(super.header, ByteData data) {
    macAddress = ascii.decode(data.buffer.asUint8List(), allowInvalid: true);
  }

  @override
  String toString() => "NetworkMacAddress: $macAddress";
}

class NetworkMacAddressAlt extends Message {
  late final String macAddress;

  NetworkMacAddressAlt(super.header, ByteData data) {
    macAddress = ascii.decode(data.buffer.asUint8List(), allowInvalid: true);
  }

  @override
  String toString() => "NetworkMacAddressAlt: $macAddress";
}

enum PhoneType {
  androidMirror(1),
  carPlay(3),
  iPhoneMirror(4),
  androidAuto(5),
  hiCar(6),

  unknown(-1);

  final int id;
  const PhoneType(this.id);

  factory PhoneType.fromId(int id) {
    return values.firstWhere((e) => e.id == id, orElse: () => unknown);
  }
}

class Plugged extends Message {
  late final PhoneType phoneType;
  late final int? wifi;

  Plugged(super.header, ByteData data) {
    final reader = BufferReader(data);
    phoneType = PhoneType.fromId(reader.getUInt32());

    final wifiAvail = data.lengthInBytes == 8;
    if (wifiAvail) {
      wifi = reader.getUInt32();

      log('wifi avail, phone type: $phoneType wifi: $wifi', tag: 'PHONE');
    } else {
      log('no wifi avail, phone type: $phoneType', tag: 'PHONE');
    }
  }

  @override
  String toString() => "Plugged: phoneType=${phoneType.name}, wifi=$wifi";
}

class Unplugged extends Message {
  Unplugged(super.header);

  @override
  String toString() => "Unplugged";
}

class AudioFormat {
  final int frequency;
  final int channel;
  final int bitrate;

  const AudioFormat({
    required this.frequency,
    required this.channel,
    required this.bitrate,
  });
}

const Map<int, AudioFormat> decodeTypeMap = {
  1: AudioFormat(frequency: 44100, channel: 2, bitrate: 16),
  2: AudioFormat(frequency: 44100, channel: 2, bitrate: 16),
  3: AudioFormat(frequency: 8000, channel: 1, bitrate: 16),
  4: AudioFormat(frequency: 48000, channel: 2, bitrate: 16),
  5: AudioFormat(frequency: 16000, channel: 1, bitrate: 16),
  6: AudioFormat(frequency: 24000, channel: 1, bitrate: 16),
  7: AudioFormat(frequency: 16000, channel: 2, bitrate: 16),
};

class AudioData extends Message {
  late final AudioCommand? command;
  late final int decodeType;
  late final double volume;
  late final double? volumeDuration;
  late final int audioType;
  late final Uint16List? data;

  AudioData(super.header, ByteData data) {
    final reader = BufferReader(data);

    decodeType = reader.getUInt32();
    volume = reader.getFloat32();
    audioType = reader.getUInt32();
    final amount = data.lengthInBytes - 12;

    AudioCommand? audioCommand;
    Uint16List? audioData;
    double? audioDuration;

    if (amount == 1) {
      audioCommand = AudioCommand.fromId(reader.getInt8());
    } else if (amount == 4) {
      audioDuration = reader.getFloat32();
    } else {
      // Create a view of just the audio data (excluding 12-byte header)
      // Use data.offsetInBytes to handle cases where data is a view into a larger buffer
      // amount = data.lengthInBytes - 12 = number of audio bytes
      // amount ~/ 2 = number of 16-bit samples
      audioData = data.buffer.asUint16List(
        data.offsetInBytes + 12,  // Start after 12-byte header
        amount ~/ 2,              // Number of 16-bit samples
      );
    }

    command = audioCommand;
    this.data = audioData;
    volumeDuration = audioDuration;
  }

  @override
  String toString() {
    String audioTypeDescription = '';
    if (command != null) {
      switch (command!) {
        case AudioCommand.AudioOutputStart:
        case AudioCommand.AudioOutputStop:
          audioTypeDescription =
              'General Audio ${command!.name.contains('Start') ? 'START' : 'STOP'}';
          break;
        case AudioCommand.AudioPhonecallStart:
        case AudioCommand.AudioPhonecallStop:
          audioTypeDescription =
              'Phone Call ${command!.name.contains('Start') ? 'START' : 'STOP'}';
          break;
        case AudioCommand.AudioSiriStart:
        case AudioCommand.AudioSiriStop:
          audioTypeDescription =
              'Voice Assistant (Siri) ${command!.name.contains('Start') ? 'START' : 'STOP'}';
          break;
        case AudioCommand.AudioNaviStart:
        case AudioCommand.AudioNaviStop:
          audioTypeDescription =
              'Navigation ${command!.name.contains('Start') ? 'START' : 'STOP'}';
          break;
        case AudioCommand.AudioMediaStart:
        case AudioCommand.AudioMediaStop:
          audioTypeDescription =
              'Music/Media ${command!.name.contains('Start') ? 'START' : 'STOP'}';
          break;
        case AudioCommand.AudioAlertStart:
        case AudioCommand.AudioAlertStop:
          audioTypeDescription =
              'Alert/Notification ${command!.name.contains('Start') ? 'START' : 'STOP'}';
          break;
        case AudioCommand.AudioInputConfig:
          audioTypeDescription = 'Microphone Config';
          break;
        default:
          audioTypeDescription = command!.name;
      }
    }

    final format = decodeTypeMap[decodeType];
    final formatInfo = format != null
        ? '${format.frequency}Hz ${format.channel}ch ${format.bitrate}bit'
        : 'unknown';

    return "AudioData: $audioTypeDescription, Format: $formatInfo, Volume: ${(volume * 100).toInt()}%, AudioType: $audioType";
  }
}

class VideoData extends Message {
  late final int width;
  late final int height;
  late final int flags;
  late final int length;
  late final int unknown;
  late final ByteBuffer? data;

  VideoData(super.header, ByteData? data) {
    if (data != null && data.lengthInBytes > 20) {
      final reader = BufferReader(data);

      width = reader.getUInt32();
      height = reader.getUInt32();
      flags = reader.getUInt32();
      length = reader.getUInt32();
      unknown = reader.getUInt32();

      this.data = data.buffer.asByteData(20).buffer;
    } else {
      width = -1;
      height = -1;
      flags = -1;
      length = -1;
      unknown = -1;

      this.data = null;
    }
  }

  @override
  String toString() =>
      "VideoData: width=$width, height=$height, flags=$flags, length=$length";
}

enum MediaType {
  data(1),
  albumCover(3),

  unknown(-1);

  final int id;
  const MediaType(this.id);

  factory MediaType.fromId(int id) {
    return values.firstWhere((e) => e.id == id, orElse: () => unknown);
  }
}

class MediaData extends Message {
  late final MediaType type;
  late final Map<String, dynamic> payload;
  // | {
  //     type: MediaType.Data
  //     media: {
  //       MediaSongName?: string
  //       MediaAlbumName?: string
  //       MediaArtistName?: string
  //       MediaAPPName?: string
  //       MediaSongDuration?: number
  //       MediaSongPlayTime?: number
  //     }
  //   }
  // | { type: MediaType.AlbumCover; base64Image: string }

  MediaData(super.header, ByteData data) {
    final reader = BufferReader(data);

    final typeInt = reader.getUInt32();
    type = MediaType.fromId(typeInt);

    if (type == MediaType.albumCover) {
      final extraData = data.buffer.asUint8List().sublist(4);
      payload = {"AlbumCover": extraData};
    } else if (type == MediaType.data) {
      final extraData = data.buffer.asUint8List().sublist(
        4,
        data.lengthInBytes - 1,
      );
      try {
        payload = jsonDecode(utf8.decode(extraData));
      } catch (e) {
        logError("MediaType.data parse error: $e", tag: 'MEDIA');
        payload = {};
      }
    } else {
      logWarn("Unexpected media type: $typeInt", tag: 'MEDIA');
      payload = {};
    }
  }

  @override
  String toString() => "MediaData: type=${type.name}";
}

class Opened extends Message {
  late final int width;
  late final int height;
  late final int fps;
  late final int format;
  late final int packetMax;
  late final int iBox;
  late final int phoneMode;

  Opened(super.header, ByteData data) {
    final reader = BufferReader(data);

    width = reader.getUInt32();
    height = reader.getUInt32();
    fps = reader.getUInt32();
    format = reader.getUInt32();
    packetMax = reader.getUInt32();
    iBox = reader.getUInt32();
    phoneMode = reader.getUInt32();
  }

  @override
  String toString() =>
      "Opened: width=$width, height=$height, fps=$fps, format=$format, packetMax=$packetMax, iBox=$iBox, phoneMode=$phoneMode";
}

class BoxInfo extends Message {
  late final Map settings;

  BoxInfo(super.header, ByteData data) {
    try {
      final str = utf8.decode(data.buffer.asUint8List(), allowMalformed: true);
      settings = jsonDecode(str);
    } catch (e) {
      logError("BoxInfo parse error: $e", tag: 'BOX');
    }
  }

  @override
  String toString() =>
      "BoxInfo: settings=${const JsonEncoder.withIndent('  ').convert(settings)}";
}

class Phase extends Message {
  late final int phase;

  Phase(super.header, ByteData data) {
    phase = BufferReader(data).getUInt32();
  }

  @override
  String toString() => "Phase: phase=$phase";
}

class AdaptrConfigurationMessage extends Message {
  final int width;
  final int height;
  final int fps;
  final String wifiType;
  final String micType;

  AdaptrConfigurationMessage(dynamic config)
    : width = config.width,
      height = config.height,
      fps = config.fps,
      wifiType = config.wifiType,
      micType = config.micType,
      super(MessageHeader(0, MessageType.Unknown));

  @override
  String toString() =>
      "AdapterConfiguration: ${width}x$height@${fps}fps wifi=$wifiType mic=$micType";
}
