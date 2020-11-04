require 'nokogiri'
require 'json'
require 'tempfile'
require 'csv'
require 'optparse'
require 'yaml'

Ntsc_max_difblocks = 1350.00

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
    line = [ @file_name, @total_frames, @total_segments, @error_percentages[0], @error_percentages[1], @error_percentages[2] ]
    return line
  end

  def get_dvrescue_xml
    @dv_meta = Nokogiri::XML`dvrescue #{@input_path}`
    @dv_meta.remove_namespaces!
  end

  def get_segment_info
    @total_frames = 0 
    @file_name = File.basename(@input_path)
    @dv_meta.xpath('/dvrescue/media/frames').each { |segment| @total_frames += segment.attribute('count').value.to_i }
    @total_segments = @dv_meta.xpath('/dvrescue/media/frames').count
    [@file_name, @total_frames, @total_segments]
  end

  def get_frame_info
    frames = @dv_meta.xpath('//frame')
    @all_frames = []
    frames.each do |parsed_frame|
      frame_info = []
      dseq_position = []
      sta_counts = []
      frame_info << parsed_frame.attribute('pts').value
      frame_info << parsed_frame.xpath('dseq').count
      parsed_frame.xpath('dseq').each do |dseq| 
        dseq_position << dseq.attribute('n').value
        sta_counts << dseq.xpath('sta').attribute('n').value.to_f
      end
      frame_info << dseq_position
      frame_info << (sta_counts.sum / Ntsc_max_difblocks * 100).to_i
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
    @error_percentages = [ten_percent, twenty_percent, more_than_twenty]
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
  headers = ['Filename', 'Total Frames', 'Total Segments', 'Error rate less than 10%', 'Error rate between 10-20%', 'Error rate above 20%']
  csv << headers
  write_to_csv.each do |line|
    csv << line
  end
end