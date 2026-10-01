#!/usr/bin/env python3
"""Copy the pinned SDK headers; add an output completion signal for bounded transport.
The verified source archive is never edited. The signal observes service replies,
not end-to-end application delivery. Fail on upstream shape drift.
"""
import pathlib
import shutil
import sys

source, destination = map(pathlib.Path, sys.argv[1:])
shutil.copytree(source, destination, dirs_exist_ok=True)
path = destination / 'pqrs/karabiner/driverkit/virtual_hid_device_service/client.hpp'
text = path.read_text()
signal = '  nod::signal<void(const std::string&)> warning_reported;'
if text.count(signal) != 1:
    raise RuntimeError('SDK warning signal shape changed')
text = text.replace(signal, signal + '\n  nod::signal<void()> output_request_completed; // WindowsMacBridge bounded-output adapter')
begin = text.index('  void async_post_report(')
end = text.index('\nprivate:', begin)
section = text[begin:end]
if section.count('report));') != 6:
    raise RuntimeError('SDK report overload shape changed')
text = text[:begin] + section.replace('report));', 'report), true);') + text[end:]
begin = text.index('  void async_request(')
end = text.index('\n  pqrs::not_null_shared_ptr_t', begin)
section = text[begin:end]
if section.count('request_buffer) {') != 1:
    raise RuntimeError('SDK request signature shape changed')
section = section.replace('request_buffer) {', 'request_buffer, bool output = false) {', 1)
section = section.replace('[this, request_buffer]', '[this, request_buffer, output]')
section = section.replace('[this](auto&& error_code', '[this, output](auto&& error_code')
section = section.replace('[this, error_code, response_buffer]', '[this, output, error_code, response_buffer]')
section = section.replace('                if (error_code)', '                if (output) output_request_completed();\n                if (error_code)')
section = section.replace('      }\n    });', '      } else if (output) {\n        output_request_completed();\n      }\n    });')
text = text[:begin] + section + text[end:]
path.write_text(text)
