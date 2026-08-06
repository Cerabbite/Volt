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

    # Safely handle empty states or lists with no media objects
    if not metadata_string or metadata_string in ("()", "[]", "[{}]"):
        return [], None

    try:
        metadata_json = json.loads(metadata_string)
        if not metadata_json or not isinstance(metadata_json, list):
            return [], None

        first_item = metadata_json[0]
        if "value" not in first_item or "audio" not in first_item["value"]:
            return [], None

        audio_data = first_item["value"]["audio"]
        if not isinstance(audio_data, dict):
            return [], None

        audios = []
        for view_key, frames in audio_data.items():
            if not isinstance(frames, dict) or "0" not in frames:
                continue

            initial_props = frames["0"]
            start_frame = int(initial_props.get("start-frame", 0))

            audios.append(
                {
                    "input": initial_props["source"],
                    "start-ms": int((start_frame / fps) * 1000),
                    "trim-start-ms": float(initial_props.get("trim-start-ms", 0.0)),
                    "trim-end-ms": float(initial_props.get("trim-end-ms", 0.0)),
                    "keyframes": frames,
                }
            )
    except Exception as e:
        print(f"Error parsing media: {e}")
        return [], None

    return audios, None


def build_audio_filter(idx, audio_info, fps, offset_ms):
    audio_path = audio_info["input"]
    start_ms = audio_info["start-ms"]
    trim_start_ms = audio_info["trim-start-ms"]
    trim_end_ms = audio_info["trim-end-ms"]
    keyframes = audio_info["keyframes"]

    adjusted_ms = start_ms - offset_ms
    skip_sec = trim_start_ms / 1000.0
    if adjusted_ms < 0:
        skip_sec += abs(adjusted_ms) / 1000.0
        adjusted_ms = 0

    filters = []

    # Trim raw audio file source bounds if requested
    trim_parts = []
    if skip_sec > 0:
        trim_parts.append(f"start={skip_sec}")
    if trim_end_ms > 0:
        trim_parts.append(f"end={trim_end_ms / 1000.0}")

    if trim_parts:
        filters.append("atrim=" + ":".join(trim_parts))
        filters.append("asetpts=PTS-STARTPTS")

    # --- DYNAMIC VOLUME EVALUATION WITH CONTINUOUS FALLBACK ---
    sorted_frames = sorted(keyframes.items(), key=lambda x: int(x[0]))
    vol_exprs = []

    last_vol = 1.0
    for frame_idx, props in sorted_frames:
        f_num = int(frame_idx)
        last_vol = float(props.get("volume", 1.0))
        vol_exprs.append(rf"eq(n\,{f_num})*{last_vol}")

    # If the video timeline runs past the last explicit keyframe,
    # inherit/sustain the last known volume instead of dropping out.
    max_keyframe_num = int(sorted_frames[-1][0]) if sorted_frames else 0

    # Construct combined statement with fallback for frames > max_keyframe_num
    combined_vol_expr = "+".join(vol_exprs)
    combined_vol_expr = f"if(gt(n,{max_keyframe_num}), {last_vol}, {combined_vol_expr})"

    filters.append(f"volume='{combined_vol_expr}':eval=frame")
    filters.append(f"adelay={adjusted_ms}|{adjusted_ms}")

    label = f"a{idx}"
    return f"[{idx}:a]{','.join(filters)}[{label}]", label


def extract_page_number(path):
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

    rendered_paths = sorted(
        temp_dir.glob(f"chunk_{chunk_index}_*.png"), key=extract_page_number
    )

    frames_bytes = []
    for p in rendered_paths:
        with open(p, "rb") as f:
            frames_bytes.append(f.read())
        p.unlink()

    return chunk_index, frames_bytes


def main():
    preview = "--preview" in sys.argv
    if preview:
        sys.argv = [a for a in sys.argv if a != "--preview"]

    num_args = check_arguments()
    input_file_path = get_input_file()

    ppi = 36 if preview else 72
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

    offset_ms = (start_sec or 0) * 1000
    filter_chains, mix_labels = [], []

    for idx, audio_info in enumerate(audios, start=1):
        ffmpeg_cmd.extend(["-i", str(audio_info["input"])])
        result = build_audio_filter(idx, audio_info, fps, offset_ms)
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
