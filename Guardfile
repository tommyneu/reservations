# NOTE: the subpath hack using a regexp group no longer works
# - instead, use the patterns option, e.g. change:
#
#    guard :less do
#      watch /^foo\/(.+)\.less/
#    end
#
#  into:
#
#    patterns = [/^foo\/(.+)\.less/]
#    guard :less, patterns: patterns do
#      patterns.each { |pattern| watch(pattern) }
#    end

less_options = {
  all_on_start: true,
  all_after_change: true,
  patterns: ['Guardfile', 'src/less/main.less'],
  output: 'public/css',
  compress: true
}

guard :less, less_options do
  less_options[:patterns].each { |pattern| watch(pattern) }
end
