package lava

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}
	cli: Cli_State = {}
	cmp: Compiler_State = {}

	if len(os.args) < 2 {
		fmt.eprintfln("E: supply proper args pls")
		os.exit(1)
	}

	switch (os.args[1]) {
	case "build":
		cli.command = .Build
		if len(os.args) < 3 {
			fmt.eprintfln("E: supply proper args pls")
			os.exit(1)
		}
		cli.dir = os.args[2]

		find_files(cli.dir, &cmp.file_names)
		build(&cmp)


	case "run":
		cli.command = .Run
		panic("todo")

	case:
		fmt.printfln("supply proper args pls")
		os.exit(1)

	}


}

find_files :: proc(dir: string, files: ^[dynamic]string) {

	if !os.is_dir(dir) {
		fmt.eprintfln("E: '%s' is not a directory", dir)
		os.exit(1)
	}

	fi, err := os.read_directory_by_path(dir, 0, context.allocator)
	if err != nil {panic("idk")}

	lava_count := 0
	for info in fi {

		if strings.has_suffix(info.fullpath, ".lava") {
			append(files, info.fullpath)
			lava_count += 1
		}
		// fmt.printfln("%#v", info)
	}
	if lava_count == 0 {
		fmt.eprintfln("E: no .lava files in '%s'", dir)
	}
	// fmt.printfln("%#v", files)

}


Commands :: enum {
	Build,
	Run,
}
Cli_State :: struct {
	command: Commands,
	dir:     string,
}


import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
