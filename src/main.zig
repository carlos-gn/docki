const std = @import("std");

const VERSION = "0.1.0";

const Config = struct {
    protected_apps: []const []const u8,
};

fn printVersion() void {
    std.debug.print("docki v{s}\n", .{VERSION});
}

fn printHelp() void {
    std.debug.print(
        \\docki - A fast app workspace manager for macOS
        \\
        \\USAGE:
        \\    docki <COMMAND> [ARGS]
        \\
        \\COMMANDS:
        \\    save <name>     Save current running apps as a preset
        \\    load <name>     Load and restore a preset
        \\    list            List all available presets
        \\    --help, -h      Show this help message
        \\    --version, -v   Show version
        \\
        \\EXAMPLES:
        \\    docki save work              # Save current apps as "work" preset
        \\    docki load work              # Restore "work" preset
        \\    docki list                   # Show all presets
        \\
        \\CONFIG:
        \\    Presets are stored in: ~/.config/docki/presets/
        \\    Optional config file: ~/.config/docki/config.json
        \\
        , .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const default_protected = [_][]const u8{ "finder", "terminal", "iterm2", "ghostty", "warp", "alacritty" };

    var protected_apps: []const []const u8 = &default_protected;
    var config: ?std.json.Parsed(Config) = null;
    var lowercased_protected = std.ArrayList([]const u8){};
    defer lowercased_protected.deinit(allocator);
    
    if (readConfigFile(allocator)) |parsed_config| {
        config = parsed_config;
        // Lowercase config protected apps to match running apps format
        for (parsed_config.value.protected_apps) |app| {
            const lowercased = try std.ascii.allocLowerString(allocator, app);
            try lowercased_protected.append(allocator, lowercased);
        }
        protected_apps = lowercased_protected.items;
    } else |_| {
        // Use defaults (already lowercase)
    }
    defer if (config) |c| c.deinit();

    if (args.len < 2) {
        printHelp();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "save")) {
        if (args.len < 3) {
            std.debug.print("Usage: docki save <preset_name>\n", .{});
            return;
        }
        const running_apps = try getRunningApps(allocator);
        defer allocator.free(running_apps);
        try savePreset(allocator, args[2], running_apps);
    } else if (std.mem.eql(u8, command, "load")) {
        if (args.len < 3) {
            std.debug.print("Usage: docki load <preset_name>\n", .{});
            return;
        }
        loadPreset(allocator, args[2], protected_apps) catch |err| {
            std.log.debug("error {any}", .{err});
            std.debug.print("Error: Preset '{s}' not found\n", .{args[2]});
        };
    } else if (std.mem.eql(u8, command, "list")) {
        try listPresets(allocator);
    } else if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printHelp();
    } else if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        printVersion();
    } else {
        std.debug.print("Error: Unknown command '{s}'\n", .{command});
        std.debug.print("Run 'docki --help' for usage information\n", .{});
    }
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 4096);
    return data;
}

fn savePreset(allocator: std.mem.Allocator, name: []const u8, running_apps: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    const preset_dir = try std.fmt.allocPrint(allocator, "{s}/.config/docki/presets", .{home});
    defer allocator.free(preset_dir);

    try std.fs.cwd().makePath(preset_dir);

    const filePath = try std.fmt.allocPrint(allocator, "{s}/{s}.apps", .{ preset_dir, name });
    defer allocator.free(filePath);

    const file = try std.fs.cwd().createFile(filePath, .{});
    defer file.close();
    _ = try file.write(running_apps);

    std.debug.print("✅ Saved preset '{s}' with running apps\n", .{name});
}

fn loadPreset(allocator: std.mem.Allocator, name: []const u8, protected_apps: []const []const u8) !void {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    const filePath = try std.fmt.allocPrint(allocator, "{s}/.config/docki/presets/{s}.apps", .{ home, name });
    defer allocator.free(filePath);

    const preset_content = try readFile(allocator, filePath);
    defer allocator.free(preset_content);

    var preset_apps = std.ArrayList([]const u8){};
    defer preset_apps.deinit(allocator);

    // 1. Collect preset apps into arraylist so we can search it multiple times
    var split_preset = std.mem.splitSequence(u8, preset_content, ",");
    while (split_preset.next()) |app| {
        const trimmed = std.mem.trim(u8, app, " \n\r");
        const lowercased =
            try std.ascii.allocLowerString(allocator, trimmed);
        try preset_apps.append(allocator, lowercased);
    }

    // 2. Get running apps
    const current_apps = try getRunningApps(allocator);
    defer allocator.free(current_apps);

    // 3. Quit apps that are runnin but NOT in the preset
    var current_apps_list = std.mem.splitSequence(u8, current_apps, ",");

    while (current_apps_list.next()) |current_app| {
        const trimmed = std.mem.trim(u8, current_app, " \n\r");

        var found = false;
        for (preset_apps.items) |preset_app| {
            if (std.mem.eql(u8, preset_app, trimmed)) {
                found = true;
                break;
            }
        }

        if (!found and !shouldNeverQuit(allocator, trimmed, protected_apps)) {
            try quitApp(allocator, trimmed);
        }
    }

    // 4. Launch apps from preset that aren't already running
    for (preset_apps.items) |preset_app| {
        var already_running = false;

        var check_apps = std.mem.splitSequence(u8, current_apps, ",");
        while (check_apps.next()) |current_app| {
            const trimmed = std.mem.trim(u8, current_app, " \n\r");
            if (std.mem.eql(u8, preset_app, trimmed)) {
                already_running = true;
                break;
            }
        }
        if (!already_running) {
            try launchApp(allocator, preset_app);
        }
        defer allocator.free(preset_app);
    }
}

fn launchApp(allocator: std.mem.Allocator, app_name: []const u8) !void {
    var child = std.process.Child.init(&[_][]const u8{ "open", "-a", app_name }, allocator);

    child.stdout_behavior = .Pipe;
    try child.spawn();

    _ = try child.wait();
}

fn listPresets(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;

    const preset_dir = try std.fmt.allocPrint(allocator, "{s}/.config/docki/presets", .{home});
    defer allocator.free(preset_dir);

    const dir = try std.fs.cwd().openDir(preset_dir, .{ .iterate = true });

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".apps")) {
            const name_without_ext = entry.name[0 .. entry.name.len - 5];
            std.debug.print("{s}\n", .{name_without_ext});
        }
    }
}

fn getRunningApps(allocator: std.mem.Allocator) ![]const u8 {
    var child = std.process.Child.init(&[_][]const u8{
        "osascript",
        "-e",
        "tell application \"System Events\" to get name of (processes where background only is false)",
    }, allocator);

    child.stdout_behavior = .Pipe;
    try child.spawn();

    const buffer = try allocator.alloc(u8, 10 * 1024 * 1024);
    defer allocator.free(buffer);
    const bytes_read = try child.stdout.?.read(buffer);
    const output = buffer[0..bytes_read];
    _ = try child.wait();

    return try std.ascii.allocLowerString(allocator, output);
}

fn quitApp(allocator: std.mem.Allocator, app_name: []const u8) !void {
    const cmd = try std.fmt.allocPrint(allocator, "quit app \"{s}\"", .{app_name});
    defer allocator.free(cmd);
    var child = std.process.Child.init(&[_][]const u8{ "osascript", "-e", cmd }, allocator);

    child.stdout_behavior = .Pipe;
    try child.spawn();

    _ = try child.wait();
}

fn shouldNeverQuit(allocator: std.mem.Allocator, app_name: []const u8, protected_apps: []const []const u8) bool {
    const lowercased_app = std.ascii.allocLowerString(allocator, app_name) catch return false;
    defer allocator.free(lowercased_app);
    
    for (protected_apps) |protected| {
        const lowercased_protected = std.ascii.allocLowerString(allocator, protected) catch continue;
        defer allocator.free(lowercased_protected);
        
        if (std.mem.eql(u8, lowercased_app, lowercased_protected)) {
            return true;
        }
    }
    return false;
}

fn readConfigFile(allocator: std.mem.Allocator) !std.json.Parsed(Config) {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;
    const config_dir = try std.fmt.allocPrint(allocator, "{s}/.config/docki/config.json", .{home});
    defer allocator.free(config_dir);

    const contents = try readFile(allocator, config_dir);
    defer allocator.free(contents);

    return std.json.parseFromSlice(Config, allocator, contents, .{ .allocate = .alloc_always });
}


