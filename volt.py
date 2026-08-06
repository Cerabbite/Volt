import sys
import json
import os
import re
import subprocess
import concurrent.futures
from pathlib import Path


def check_arguments():
    if len(sys.argv) not in (2, 3):
        print(f"Usage: {sys.argv[0]} <typst_file> [start_sec/end_sec] [--preview]")
        sys.exit(1)
    return len(sys.argv)


def get_input_file():
    input_file_path = Path(sys.argv[1])
    if not input_file_path.is_file():
        print(f"Error: File '{input_file_path}' not found.")
        sys.exit(1)
    return input_file_path


def extract_metadata(input_file_path):
    print(f"Extracting metadata from {input_file_path}...")
    command = ["typst", "eval", "query(<editor-config>)", "--in", str(input_file_path)]
    result = subprocess.run(command, capture_output=True, text=True)
    metadata_string = result.stdout.strip()

    if not metadata_string or metadata_string in ("()", "[]"):
        print(f"Error: Could not find <editor-config> metadata in {input_file_path}.")
        sys.exit(1)

    try:
        metadata_json = json.loads(metadata_string)
        fps = metadata_json[0]["value"]["fps"]
        total_frames = metadata_json[0]["value"]["duration"]
        if fps is None or total_frames is None:
            raise ValueError
    except Exception:
        print("Error: Failed to parse 'fps' or 'duration' from metadata.")
        sys.exit(1)

    return int(fps), int(total_frames)


def extract_media(input_file_path, fps):
    print(f"Extracting media from {input_file_path}...")
    command = ["typst", "eval", "query(<media-state>)", "--in", str(input_file_path)]
    result = subprocess.run(command, capture_output=True, text=True)
    metadata_string = result.stdout.strip()

    if not metadata_string or metadata_string in ("()", "[]"):
        return [], None

    try:
        metadata_json = json.loads(metadata_string)
        audios = []
        for audio in metadata_json[0]["value"]["audio"]:
            audios.append(
                [
                    audio["input"],
                    int((audio["start-frame"] / fps) * 1000),
                    float(audio["cutoff"] / fps),
                    float(
                        audio.get("fade-out", 0) / fps
                    ),  # Convert fade-out frames to seconds
                    float(audio["volume"]),
                ]
            )
    except Exception as e:
        print(f"Error parsing media: {e}")
        sys.exit(1)

    return audios, None


def build_audio_filter(
    idx, audio_path, start_ms, cutoff_sec, fade_out_sec, volume, offset_ms
):
    adjusted_ms = start_ms - offset_ms
    skip_sec = 0.0
    if adjusted_ms < 0:
        skip_sec = abs(adjusted_ms) / 1000.0
        adjusted_ms = 0

    if cutoff_sec > 0 and cutoff_sec <= skip_sec:
        return None

    filters = []
    trim_parts = []
    if skip_sec > 0:
        trim_parts.append(f"start={skip_sec}")
    if cutoff_sec > 0:
        trim_parts.append(f"end={cutoff_sec}")

    if trim_parts:
        filters.append("atrim=" + ":".join(trim_parts))
        filters.append("asetpts=PTS-STARTPTS")

    # Add audio fade-out filter if cutoff and fade_out_sec are provided
    if cutoff_sec > 0 and fade_out_sec > 0:
        effective_duration = cutoff_sec - skip_sec
        fade_start = max(0.0, effective_duration - fade_out_sec)
        actual_fade_dur = min(fade_out_sec, effective_duration)
        # Using curve=exp or curve=cbr gives a smooth bezier-like natural audio dropoff
        filters.append(
            f"afade=t=out:st={fade_start:.3f}:d={actual_fade_dur:.3f}:curve=exp"
        )

    filters.append(f"volume={volume}")
    filters.append(f"adelay={adjusted_ms}|{adjusted_ms}")

    label = f"a{idx}"
    return f"[{idx}:a]{','.join(filters)}[{label}]", label


def extract_page_number(path):
    """Extract integer page/frame index for accurate numerical sorting."""
    match = re.search(r"_(\d+)\.png$", path.name)
    return int(match.group(1)) if match else 0


def render_chunk_to_bytes(
    input_file_path, chunk_index, start_f, end_f, ppi, temp_dir, preview=False
):
    is_preview_str = "true" if preview else "false"
    chunk_pattern = temp_dir / f"chunk_{chunk_index}_{{0p}}.png"
    command = [
        "typst",
        "compile",
        str(input_file_path),
        str(chunk_pattern),
        "--input",
        f"start-frame={start_f}",
        "--input",
        f"end-frame={end_f}",
        "--input",
        f"preview={is_preview_str}",
        "--ppi",
        str(ppi),
    ]
    res = subprocess.run(command, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Typst compilation error:\n{res.stderr}")

    # Read rendered PNGs IN NUMERICAL ORDER
    rendered_paths = sorted(
        temp_dir.glob(f"chunk_{chunk_index}_*.png"), key=extract_page_number
    )

    frames_bytes = []
    for p in rendered_paths:
        with open(p, "rb") as f:
            frames_bytes.append(f.read())
        p.unlink()  # Immediate cleanup of temporary image file

    return chunk_index, frames_bytes


def main():
    preview = "--preview" in sys.argv
    if preview:
        sys.argv = [a for a in sys.argv if a != "--preview"]

    num_args = check_arguments()
    input_file_path = get_input_file()

    ppi = 36 if preview else 72  # 144 for 4k
    preset = "p1" if preview else "p6"
    crf = 30 if preview else 23

    start_sec, end_sec = None, None
    if num_args == 3:
        args = sys.argv[2].split("/")
        start_sec = int(args[0])
        end_sec = int(args[1])

    fps, total_frames = extract_metadata(input_file_path)

    if start_sec is not None and end_sec is not None:
        start_frame = start_sec * fps
        end_frame = end_sec * fps
    else:
        start_frame = 0
        end_frame = total_frames

    total_to_render = end_frame - start_frame + 1
    duration_sec = total_to_render / fps

    audios, _ = extract_media(input_file_path, fps)

    # Configure FFmpeg pipe reader
    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "image2pipe",
        "-vcodec",
        "png",
        "-r",
        str(fps),
        "-i",
        "pipe:0",
    ]

    # Handle Audio Streams
    offset_ms = (start_sec or 0) * 1000
    filter_chains, mix_labels = [], []

    for idx, (audio_path, start_ms, cutoff_sec, fade_out_sec, volume) in enumerate(
        audios, start=1
    ):
        ffmpeg_cmd.extend(["-i", str(audio_path)])
        result = build_audio_filter(
            idx, audio_path, start_ms, cutoff_sec, fade_out_sec, volume, offset_ms
        )
        if result:
            chain, label = result
            filter_chains.append(chain)
            mix_labels.append(f"[{label}]")

    if filter_chains:
        if len(filter_chains) == 1:
            filter_complex = filter_chains[0].rsplit("[", 1)[0] + "[aout]"
        else:
            mix_filter = f"{''.join(mix_labels)}amix=inputs={len(filter_chains)}:duration=first[aout]"
            filter_complex = ";".join(filter_chains) + ";" + mix_filter

        ffmpeg_cmd.extend(
            ["-filter_complex", filter_complex, "-map", "0:v", "-map", "[aout]"]
        )
    else:
        ffmpeg_cmd.extend(["-map", "0:v"])

    output_video_path = input_file_path.with_suffix(".mp4")

    # Limit output duration explicitly to match requested clip
    ffmpeg_cmd.extend(
        [
            "-t",
            str(duration_sec),
            "-c:v",
            "h264_nvenc",
            "-preset",
            preset,
            "-tune",
            "hq",
            "-rc",
            "vbr",
            "-cq",
            str(crf),
            "-b:v",
            "0",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            str(output_video_path),
        ]
    )

    print("Launching FFmpeg streaming process...")
    ffmpeg_proc = subprocess.Popen(ffmpeg_cmd, stdin=subprocess.PIPE)

    cpu_count = os.cpu_count() or 4
    temp_dir = Path("./.frames_tmp")
    temp_dir.mkdir(exist_ok=True)

    # SMART THRESHOLD: If rendering < 500 frames (small clip/preview),
    # run 1 single Typst process to avoid CLI re-parsing penalty.
    if total_to_render < 500:
        print(
            f"Rendering {total_to_render} frames in 1 single Typst call (Fast Path)..."
        )
        _, frame_bytes_list = render_chunk_to_bytes(
            input_file_path, 0, start_frame, end_frame, ppi, temp_dir, preview=preview
        )
        try:
            for img_bytes in frame_bytes_list:
                ffmpeg_proc.stdin.write(img_bytes)
            ffmpeg_proc.stdin.flush()
        except (BrokenPipeError, IOError):
            pass
    else:
        # High Frame Count: Parallelize across cores
        chunk_size = max(150, (total_to_render + cpu_count - 1) // cpu_count)
        chunks = []
        curr = start_frame
        c_idx = 0
        while curr <= end_frame:
            c_end = min(end_frame, curr + chunk_size - 1)
            chunks.append((c_idx, curr, c_end))
            curr += chunk_size
            c_idx += 1

        print(
            f"Parallel rendering {total_to_render} frames across {cpu_count} CPU cores in {len(chunks)} chunks..."
        )

        with concurrent.futures.ProcessPoolExecutor(max_workers=cpu_count) as executor:
            future_to_chunk = {
                executor.submit(
                    render_chunk_to_bytes,
                    input_file_path,
                    c[0],
                    c[1],
                    c[2],
                    ppi,
                    temp_dir,
                ): c[0]
                for c in chunks
            }

            results_map = {}
            next_chunk_to_write = 0
            pipe_broken = False

            for future in concurrent.futures.as_completed(future_to_chunk):
                chunk_idx, frame_bytes_list = future.result()
                results_map[chunk_idx] = frame_bytes_list

                while next_chunk_to_write in results_map:
                    if not pipe_broken:
                        try:
                            for img_bytes in results_map[next_chunk_to_write]:
                                ffmpeg_proc.stdin.write(img_bytes)
                            ffmpeg_proc.stdin.flush()
                        except (BrokenPipeError, IOError):
                            pipe_broken = True

                    del results_map[next_chunk_to_write]
                    next_chunk_to_write += 1

    try:
        if ffmpeg_proc.stdin:
            ffmpeg_proc.stdin.close()
    except (BrokenPipeError, IOError):
        pass

    ffmpeg_proc.wait()

    if temp_dir.exists():
        for p in temp_dir.glob("*"):
            p.unlink()
        temp_dir.rmdir()

    print(f"Done! Video exported to {output_video_path}")


if __name__ == "__main__":
    main()
