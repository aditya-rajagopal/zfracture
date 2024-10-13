pub const TTYError = error{UnableToGetConsoleScreenBuffer};

pub fn get_tty_config(file: std.fs.File) TTYError!std.io.tty.Config {
    var info: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (std.os.windows.kernel32.GetConsoleScreenBufferInfo(file.handle, &info) != std.os.windows.TRUE) {
        return TTYError.UnableToGetConsoleScreenBuffer;
    }
    return std.io.tty.Config{ .windows_api = .{
        .handle = file.handle,
        .reset_attributes = info.wAttributes,
    } };
}

const std = @import("std");
