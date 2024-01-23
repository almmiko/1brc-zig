const std = @import("std");
const debug = std.debug.print;

const c = @cImport({
    @cInclude("string.h");
});

const btree = @cImport({
    @cInclude("btree.h");
});

const Data = struct {
    min: f64,
    max: f64,
    count: f64,
    sum: f64,
    mean: f64,
};

const Context = struct {
    key: []const u8,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var tree: *btree.struct_btree = undefined;

var global_store = std.StringHashMap(Data).init(allocator);
var maps_store = std.ArrayList(std.StringHashMap(Data)).init(allocator);

const Wrapper = struct {
    pub fn compare(a: ?*const anyopaque, b: ?*const anyopaque, udata: ?*anyopaque) callconv(.C) c_int {
        _ = udata;

        const ctx_a: *Context = @ptrCast(@alignCast(@constCast(a)));
        const ctx_b: *Context = @ptrCast(@alignCast(@constCast(b)));

        const key_a_size = ctx_a.key.len;
        const key_b_size = ctx_b.key.len;

        if (key_a_size == key_b_size) {
            return c.strncmp(ctx_a.key.ptr, ctx_b.key.ptr, key_b_size);
        }

        const min_size = @min(key_a_size, key_b_size);

        const cmp = c.strncmp(ctx_a.key.ptr, ctx_b.key.ptr, min_size);

        if (cmp == 0) {
            if (key_a_size > key_b_size) {
                const casted: i32 = @intCast(ctx_a.key[min_size]);
                return casted - '\x00';
            } else {
                const casted: i32 = @intCast(ctx_b.key[min_size]);
                return '\x00' - casted;
            }
        }

        return cmp;
    }

    pub fn iter(a: ?*const anyopaque, udata: ?*anyopaque) callconv(.C) bool {
        const counter: *usize = @ptrCast(@alignCast(udata));

        const ctx: *Context = @ptrCast(@alignCast(@constCast(a)));

        const entry = global_store.get(ctx.key).?;

        const stdout = std.io.getStdOut().writer();

        const tree_size = btree.btree_count(tree);

        stdout.print("{s}={d:.1}/{d:.1}/{d:.1}", .{ ctx.key, entry.min, entry.sum / entry.count, entry.max }) catch unreachable;

        if (counter.* + 1 < tree_size) {
            stdout.print(", ", .{}) catch unreachable;
            counter.* += 1;
        }

        return true;
    }
};

pub fn process(chunk: []u8, wg: *std.Thread.WaitGroup) void {
    defer wg.finish();

    var store = std.StringHashMap(Data).init(allocator);

    var line_start: usize = 0;

    while (line_start < chunk.len) {
        const line_end = std.mem.indexOfScalarPos(u8, chunk, line_start, '\n').?;
        const line = chunk[line_start..line_end];

        line_start = line_end + 1;

        const pos = std.mem.indexOfScalarPos(u8, line, 0, ';').?;
        const station = line[0..pos];
        const temp_str = line[pos + 1 ..];

        const temp_number = std.fmt.parseFloat(f64, temp_str) catch unreachable;

        const store_value = store.getOrPut(station) catch unreachable;
        if (!store_value.found_existing) {
            store_value.value_ptr.* = .{ .min = temp_number, .max = temp_number, .count = 1, .sum = temp_number, .mean = 0.0 };
        } else {
            store_value.value_ptr.* = .{
                .min = @min(store_value.value_ptr.min, temp_number),
                .max = @max(store_value.value_ptr.max, temp_number),
                .count = store_value.value_ptr.count + 1,
                .sum = store_value.value_ptr.sum + temp_number,
                .mean = store_value.value_ptr.mean,
            };
        }

        if (line_end >= chunk.len) break;
    }

    maps_store.append(store) catch unreachable;
}

pub fn deinitGlobals() void {
    global_store.deinit();
    maps_store.deinit();

    btree.btree_free(tree);
}

pub fn run() !void {
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip();

    const file_name = args.next() orelse "data/measurements.txt";

    tree = btree.btree_new(@sizeOf(Context), 0, Wrapper.compare, null).?;

    const cpus = try std.Thread.getCpuCount();

    try maps_store.ensureTotalCapacity(cpus);

    var pool: std.Thread.Pool = undefined;
    var wg = std.Thread.WaitGroup{};

    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    var file = try std.fs.cwd().openFile(file_name, .{ .mode = .read_only });
    defer file.close();

    const file_len: usize = @as(usize, try file.getEndPos());

    const file_in_memory = try std.os.mmap(null, file_len, std.os.PROT.READ, std.os.MAP.PRIVATE, file.handle, 0);
    defer std.os.munmap(file_in_memory);

    // don't chunk small files
    const workers = if (file_len < 500) 1 else cpus;

    var chunk_start: usize = 0;

    for (0..workers) |i| {
        const chunk_end = std.mem.indexOfScalarPos(u8, file_in_memory, file_len / workers * (i + 1), '\n') orelse file_len - 1;
        const chunk = file_in_memory[chunk_start .. chunk_end + 1];

        wg.start();

        try pool.spawn(process, .{ chunk, &wg });

        chunk_start = chunk_end + 1;
        if (chunk_start >= file_len) break;
    }

    pool.waitAndWork(&wg);

    for (maps_store.items) |map| {
        var it = map.iterator();

        while (it.next()) |record| {
            const store_value = global_store.getOrPut(record.key_ptr.*) catch unreachable;
            if (!store_value.found_existing) {
                store_value.value_ptr.* = record.value_ptr.*;

                _ = btree.btree_set(tree, &Context{ .key = record.key_ptr.* });
            } else {
                store_value.value_ptr.* = .{
                    .min = @min(store_value.value_ptr.min, record.value_ptr.min),
                    .max = @max(store_value.value_ptr.max, record.value_ptr.max),
                    .count = store_value.value_ptr.count + 1,
                    .sum = store_value.value_ptr.sum + record.value_ptr.sum,
                    .mean = store_value.value_ptr.mean,
                };
            }
        }
    }

    const stdout = std.io.getStdOut().writer();
    stdout.print("{{", .{}) catch unreachable;

    var counter: usize = 0;

    _ = btree.btree_ascend(tree, null, Wrapper.iter, &counter);

    stdout.print("}}\n", .{}) catch unreachable;

    defer deinitGlobals();
}

pub fn main() !void {
    try run();
}
