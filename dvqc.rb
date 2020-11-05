require 'nokogiri'
require 'json'
require 'tempfile'
require 'csv'
require 'optparse'
require 'yaml'

Ntsc_max_difblocks = 1350.00
Ntsc_dif_seqs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

def check_for_dv(target)
  target_data = JSON.parse(`mediainfo --Output=JSON #{target}`)
  return true if target_data['media']['track'][1]['Format'] = 'DV'
end


class QcTarget
  def initialize(value)
    @input_path = value
    @warnings = []
  end

  def output_csv_line
    line = [ @file_name, @total_frames, @total_segments, @segment_characteristics, @error_percentages[0], @error_percentages[1], @error_percentages[2], @error_percentages[3] ]
    return line
  end

  def get_dvrescue_xml
    @dv_meta = Nokogiri::XML`dvrescue #{@input_path}`
    @dv_meta.remove_namespaces!
  end

  def get_segment_info
  	@audio_rates = []
  	@video_rates = []
  	@chroma_subsamplings = []
  	@aspect_ratios = []
  	@channels = []
    @total_frames = 0 
    @file_name = File.basename(@input_path)
    @dv_meta.xpath('/dvrescue/media/frames').each { |segment| @audio_rates << segment.attribute('audio_rate').value unless segment.attribute('audio_rate').nil?}
    @dv_meta.xpath('/dvrescue/media/frames').each { |segment| @video_rates << segment.attribute('video_rate').value }
    @dv_meta.xpath('/dvrescue/media/frames').each { |segment| @chroma_subsamplings << segment.attribute('chroma_subsampling').value unless segment.attribute('chroma_subsampling').nil? }
    @dv_meta.xpath('/dvrescue/media/frames').each { |segment| @aspect_ratios << segment.attribute('aspect_ratio').value unless segment.attribute('aspect_ratio').nil? }
    @dv_meta.xpath('/dvrescue/media/frames').each { |segment| @channels << segment.attribute('channels').value unless segment.attribute('channels').nil? }
    @dv_meta.xpath('/dvrescue/media/frames').each { |segment| @total_frames += segment.attribute('count').value.to_i }
    @segment_characteristics = [@audio_rates.uniq, @video_rates.uniq, @chroma_subsamplings.uniq, @aspect_ratios.uniq, @channels.uniq]
    @total_segments = @dv_meta.xpath('/dvrescue/media/frames').count
    [@file_name, @total_frames, @total_segments, @segment_characteristics]
  end

  def get_frame_info
    frames = @dv_meta.xpath('//frame')
    @all_frames = []
    frames.each do |parsed_frame|
      frame_info = []
      dseq_position = []
      sta_counts = []
      frame_info << parsed_frame.attribute('pts').value
      if (parsed_frame.attribute('full_conceal_vid').nil? || parsed_frame.attribute('full_conceal').nil?)
        frame_info << parsed_frame.xpath('dseq').count
        parsed_frame.xpath('dseq').each do |dseq|
          dseq_position << dseq.attribute('n').value
          sta_counts << dseq.xpath('sta').attribute('n').value.to_f
        end
        frame_info << dseq_position
        frame_info << (sta_counts.sum / Ntsc_max_difblocks * 100).to_i
      else
        frame_info << Ntsc_dif_seqs
        frame_info << 100
      end
      @all_frames << frame_info
    end
    return @all_frames
  end

  def sort_error_percentages
    ten_percent = 0
    twenty_percent = 0
    more_than_twenty = 0
    @all_frames.each do |frame_errors|  
      error_percent = frame_errors[3]
      ten_percent += 1 if (error_percent <= 10 && error_percent != 0)
      twenty_percent += 1 if (error_percent <= 20 && error_percent > 10)
      more_than_twenty += 1 if error_percent >= 21
    end
    percent_error_frame = (@all_frames.count.to_f / @total_frames * 100).round(2)
    @error_percentages = [ten_percent, twenty_percent, more_than_twenty, percent_error_frame]
  end
end

dv_files = []
write_to_csv = []
ARGV.each do |input|
  dv_files << input if check_for_dv(input)
end

dv_files.each do |target_file|
target = QcTarget.new(File.expand_path(target_file))
  target.get_dvrescue_xml
  target.get_segment_info
  target.get_frame_info
  target.sort_error_percentages
  write_to_csv << target.output_csv_line
end

timestamp = Time.now.strftime('%Y-%m-%d_%H-%M-%S')
output_csv = ENV['HOME'] + "/Desktop/dvqc_out_#{timestamp}.csv"

CSV.open(output_csv, 'wb') do |csv|
  headers = ['Filename', 'Total Frames', 'Total Segments', 'Segment Characteristics', 'Error rate less than 10%', 'Error rate between 10-20%', 'Error rate above 20%', 'Percent of frames with errors']
  csv << headers
  write_to_csv.each do |line|
    csv << line
  end
end